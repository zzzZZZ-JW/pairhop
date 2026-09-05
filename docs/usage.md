# 使用与故障排查

## 安装内容

安装以当前登录用户运行，不使用 root。`install` 生成适合当前用户的 plist，不发布包含个人绝对路径的预制配置。

| 内容 | 路径 |
|---|---|
| CLI 软链接 | `~/.local/bin/pairhop` |
| 原生可执行文件 | `~/Library/Application Support/ChromeICloudPairingHelper/pairing-helper` |
| 状态及最近 200 次结果 | 同目录 `state.json`、`attempts.jsonl` |
| LaunchAgent | `~/Library/LaunchAgents/com.zhangjiawei.chrome-icloud-pairing.plist` |

程序目录权限为 700，配置及记录文件为 600。命令链接已有其他归属时，安装会拒绝覆盖；卸载只删除仍指向本工具的命令链接，保留用户的 `.local/bin` 和 shell 配置。

技术名称 `pairing-helper`、安装目录和签名标识沿用早期版本，目的是保留 macOS 已有的授权关系；日常命令名称为 `pairhop`。

## 更新或重装

运行目标版本 README 中的版本固定安装命令。安装会停止旧服务、替换二进制、重新生成配置并启动。不会修改 Chrome、iCloud 数据或扩展文件。

`pairhop install` 从当前正在运行的二进制重新安装，不联网检查版本。卸载后软链接也会删除；再次安装需要重新执行发布版安装命令。

## 权限

所有管理命令都可在终端运行；macOS 的首次授权必须由用户操作系统设置。源码构建、修改签名身份或路径可能触发重新授权。不要通过修改 TCC 数据库来跳过系统授权。

安装后允许辅助功能中的 `pairing-helper`，再运行：

```sh
pairhop stop
pairhop start
pairhop status
```

若系统仍显示未授权，检查列表中的文件是否来自上面的正式安装路径。CLI 状态第一行是当前 launchd 状态；后面的 JSON 是带 `updatedAt` 时间戳的快照，服务停止时可能是旧快照。

## 不输入或输入中止

1. 先运行 `pairhop status`，检查权限和 `automaticInputEnabled`。
2. 确认当前是 Google Chrome 和 Apple 的官方扩展，且系统配对码与六格输入界面同时存在。
3. 六格必须全部为空、第一格获得焦点。触发配对后避免切换应用或手动输入。
4. 一次请求中止后，关闭当前配对窗口并重新触发；助手不尝试清空或修复已输入的内容。

状态中 `lastSkipReason`、`lastAttempt.reason` 记录简短原因，不含验证码。`confirmed` 表示看到了官方已连接界面的正向证据；`submitted_unconfirmed` 只表示六位已发送，未确认连接；`aborted` 表示提前停止。不要把输入完成等同于连接成功。

Chrome 关闭时 `chromeProcesses: 0` 正常。首版只匹配已验证的简体中文和英语连接文案；其他语言可能出现已输入但无法确认的状态。

## 诊断模式

```sh
pairhop install --diagnostic
pairhop diagnose
# 恢复自动输入
pairhop install
```

诊断模式不发送数字。`status` / `diagnose` 会发起一次显式检查并更新状态，不是后台周期扫描。

## 卸载

```sh
pairhop uninstall
```

这会停止并停用自动启动，删除本工具的安装文件及记录。macOS 管理的辅助功能授权项可能仍留在列表里，可自行删除。Chrome 扩展和钥匙串数据不属于本工具，不随卸载删除。

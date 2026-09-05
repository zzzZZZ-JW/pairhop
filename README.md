# PairHop

**把 Mac 显示的 iCloud 配对码，接到 Chrome 的官方扩展。**

[English](docs/README.en.md) · [使用与故障排查](docs/usage.md) · [实测数据](docs/performance.md) · [MIT License](LICENSE)

你点击 Chrome 的「启用密码自动填充」，PairHop 读取 Apple 系统窗口中的六位配对码，逐位输入官方 **iCloud 密码**扩展，并检查连接结果。省去看码、记码和手动输入。

Swift 原生后台程序，由用户级 LaunchAgent 管理。**没有 `.app`、菜单栏或 Dock 图标；安装和日常管理全部通过命令行。** 登录后待命，终端可以关闭。首次辅助功能授权仍需你在 macOS 系统设置中确认。

> **v0.1.1 预览版**：提供 Apple Silicon 二进制，已用 Developer ID 签名，尚未公证。当前实机验证组合为 macOS 27.0 Beta、Chrome 152、官方扩展 3.3.0。项目最低编译目标为 macOS 14，其他系统、语言及输入法组合尚未完成兼容验收。

## 安装

先安装 Chrome 中 Apple 发布的 [iCloud 密码扩展](https://chromewebstore.google.com/detail/icloud-passwords/pejdijmoenmkgeppbflobdenhhabjlaj)，并在这台 Mac 上配置好 iCloud 密码。

在 **Apple Silicon Mac 的原生终端**执行，无需 `sudo`、Homebrew 或 Xcode：

```sh
curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/zzzZZZ-JW/pairhop/v0.1.1/install.sh | /bin/bash
export PATH="$HOME/.local/bin:$PATH"
pairhop status
```

安装脚本固定下载 v0.1.1，并在执行前校验 SHA-256、Apple 签名链、签名团队和程序标识。也可以先下载并阅读 [install.sh](install.sh) 再执行。

首次使用，打开「系统设置 → 隐私与安全性 → 辅助功能」，允许 **pairing-helper**。列表中没有它时，点「＋」，按 `⌘⇧G` 输入下面的目录，选择 `pairing-helper`：

```text
~/Library/Application Support/ChromeICloudPairingHelper/
```

授权后执行 `pairhop stop && pairhop start && pairhop status`。`accessibilityAuthorized`、`inputAuthorized`、`automaticInputEnabled` 应为 `true`，正常待命状态为 `ready`。

`export PATH` 只影响当前终端。要让以后打开的 zsh 终端也能直接使用命令，可将 `export PATH="$HOME/.local/bin:$PATH"` 加入 `~/.zprofile`；也可始终使用 `"$HOME/.local/bin/pairhop"`。

## 日常操作

| 命令 | 行为 |
|---|---|
| `pairhop status` | 查询后台进程、权限、模式及最近一次结果 |
| `pairhop stop` | 停止运行，**同时停用登录自动启动** |
| `pairhop start` | 恢复运行，同时启用登录自动启动 |
| `pairhop install --diagnostic` | 切换为只检测、不输入的诊断模式 |
| `pairhop install` | 安装或恢复自动输入模式 |
| `pairhop uninstall` | 删除程序、自有命令链接、启动配置和本工具的记录 |
| `pairhop version` | 查看版本 |

然后正常使用 Chrome：**点击启用填充 → Apple 显示配对码 → PairHop 自动输入 → 官方扩展确认连接。** 成功时没有额外提示音或窗口。后续密码访问及 Touch ID 验证仍由 Apple 处理。

## 功能亮点

- **事件驱动待命**：稳定空闲没有周期扫描定时器；只有配对请求内存在有界的短暂重读。
- **按需快速执行**：提前准备监听与输入组件，配对任务使用 `userInitiated` QoS，维护任务使用 `utility`。输入关键路径不启动 shell、不请求网络、不同步写日志。
- **目标严格检查**：验证 Apple 帮助程序和 Google Chrome 的运行代码签名，匹配官方扩展的完整来源与页面路径，要求唯一来源、唯一目标、六格为空且焦点正确。
- **逐位检查**：只接受六位 ASCII 数字，保留前导零；向 Chrome PID 定向发送按键，检查输入进度、焦点和硬件输入计数。检测到手动输入、目标变化、权限失效或超时便停止，保留官方手动流程。
- **本地处理**：验证码不进入剪贴板、文件或日志；不使用 OCR，不读取网站保存的密码。后台不访问网络，安装脚本仅从 GitHub 下载。
- **轻量管理**：没有防休眠断言。异常退出由 launchd 限速恢复；运行记录仅保留最近 200 次简短结果。

## 实测，而不是承诺

同一台 Mac 的 **v0.1.0 配对引擎基线**完成 30 次独立 Chrome 退出、重启和真实配对，30/30 确认连接：

| 指标 | 中位数 | P95 |
|---|---:|---:|
| 来源、输入框、焦点已就绪 → 六位输入完成 | 129.9 ms | **155.9 ms** |
| 助手发现请求 → 官方扩展确认连接 | 593.9 ms | **646.1 ms** |

交流电、Chrome 关闭、无分析器的 15 分钟待命：平均 CPU 约 **0.000181%**（一个逻辑 CPU 为 100%），约 **6 MiB** 物理 footprint，磁盘写入增量为零。它不代表整机功耗，也不证明长期无泄漏。

v0.1.1 增加命令链接和发布安装流程；配对引擎文件保持不变。**上述 30 次与 15 分钟数据不是对 v0.1.1 二进制的重新测量。** 完整口径、基线哈希、数据表和未完成项目见 [实测报告](docs/performance.md)。

## 边界

PairHop 是独立开源项目，与 Apple、Google 无隶属或背书关系。它完成官方要求的配对码输入，不修改扩展、不解密钥匙串，也不取消 Touch ID。

辅助功能读取与按键发送不是原子操作，无法承诺任意毫秒级焦点竞争下绝对零误输入。源码中的逐位检查用于降低这个风险。Apple、Chrome 或扩展更新界面后可能需要适配；遇到不明确的情况应使用官方手动配对，不应放宽来源检查。

Intel、中文输入法实机测试、真正注销登录、睡眠唤醒、运行中撤权、多请求竞争、电池及低电量模式、数天稳定性等仍待验证。发布二进制未公证，不提供绕过 Gatekeeper 的安装步骤。详见 [安全模型](SECURITY.md)。

## 从源码构建

需要 macOS 和 Swift 6 或更新版本的工具链：

```sh
git clone https://github.com/zzzZZZ-JW/pairhop.git
cd pairhop
./scripts/test.sh
./scripts/build.sh
"$(swift build -c release --show-bin-path)/pairing-helper" install
```

默认使用本机临时签名（ad hoc）。长期使用应设置自己的稳定签名身份：

```sh
PAIRHOP_SIGNING_IDENTITY='你的签名身份名称或 SHA-1' ./scripts/build.sh
```

需要指定 Xcode 时设置 `DEVELOPER_DIR`。源码构建不要求使用作者证书；官方预编译安装脚本则仅接受指定发布者签名。安装路径及 LaunchAgent 标识沿用首版，以维持已有辅助功能授权。详见 [开发说明](CONTRIBUTING.md)。

由 **[zzzZZZ](https://github.com/zzzZZZ-JW)** 创建与维护，按 [MIT](LICENSE) 许可证开源。

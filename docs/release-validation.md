# v0.1.1 发布验证

日期：2026-09-05。以下检查针对发布二进制，不将 v0.1.0 的重复配对样本冒充为此版本测试。

```text
Asset: pairhop-v0.1.1-macos-arm64
Size: 411648 bytes
SHA-256: f93c9c2bd0660c45af0b14de3a2f1001f17d5648d57a76cec9d1a239d032334b
```

| 本机检查 | 结果 |
|---|---|
| Swift release 编译 | 通过 |
| Apple Silicon arm64 架构 | 通过 |
| Developer ID 签名、Hardened Runtime | 通过 |
| 安装器使用的 Apple 链 / Team / Identifier 校验表达式 | 对真实发布二进制校验通过 |
| 源码和二进制中的本机绝对路径、私人邮箱扫描 | 无匹配 |
| 六位解析、前导零、来源 URL、输入进度 | 4 项 XCTest 通过 |
| 归属链接重装、外来文件和悬空链接保护 | 2 项 XCTest 通过 |
| 安装器下载失败、哈希错误、签名错误时不执行；成功时执行且清理临时文件 | 4 项离线夹具测试通过 |
| `pairhop version`、帮助及 PATH 调用 | 通过 |
| 通过 PATH 执行 `pairhop install` | 通过 |
| LaunchAgent 自动模式启动 | 通过 |
| 既有辅助功能和输入权限连续性 | 通过 |
| stop 停止并停用登录启动、start 恢复 | 通过 |
| uninstall 删除自有链接、程序目录和 plist | 通过 |
| 最后重装并恢复自动运行 | 通过 |

[公开 CI](https://github.com/zzzZZZ-JW/pairhop/actions) 检查另一个 macOS runner 的源码构建、规则、链接和安装器夹具，不触发系统授权或真实配对。发布后的 GitHub 下载与安装验证结果记录在 [v0.1.1 Release](https://github.com/zzzZZZ-JW/pairhop/releases/tag/v0.1.1)。

安装器夹具仅在临时脚本副本中替换下载和签名工具；未调用真实 LaunchAgent。真实签名表达式和真实安装/卸载由独立本机检查覆盖。

**尚未完成**：公证、另一台 Mac 首次授权/Gatekeeper 流程，以及 [性能报告](performance.md) 中列出的其他真实设备验收项。

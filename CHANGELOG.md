# 更新日志

本项目遵循语义化版本的版本号形式，并在此记录面向用户的重要变更。

AG Bridge 基于上游 Antigravity Bridge v2.2.0 改造而来。上游自 v2.2.0 起的变更历史见
[上游 CHANGELOG](https://github.com/anzaiyes/AntigravityBridge/blob/main/CHANGELOG.md)；
本文件只记录 AG Bridge 自身的变更。

## [1.0.0] - 2026-09-19

首个版本，基于上游 Antigravity Bridge v2.2.0。

### 新增

- 同时支持 Google 拆分出的两个独立 App：`com.google.antigravity-ide`（Antigravity IDE）
  与 `com.google.antigravity`（Antigravity / agent manager）。上游只支持前者。
- 新增 `--version` 与 `--help` 参数。
- 应用图标补齐 16→1024 全部尺寸（含 @2x 共 10 个），上游仅 5 个基础尺寸。
- 新增 `AG_BRIDGE_CONFIG_DIR` 环境变量；旧版 `ANTIGRAVITY_BRIDGE_CONFIG_DIR`、
  `ANTIGRAVITY_PROXY_CONFIG_DIR` 继续兼容。
- 新增 `AG_BRIDGE_LIBRARY_ONLY` 环境变量；旧版 `ANTIGRAVITY_PROXY_LIBRARY_ONLY` 继续兼容。

### 修复

- **修复启动器可能永久卡死**：上游用 AppleScript 按应用名 `"Antigravity IDE"` 判断
  Antigravity 是否在运行。当机器上不存在该显示名的 App 时，`osascript` 会一直阻塞，
  导致双击启动器后没有任何反应、进程也无法退出。现改为按真实可执行文件路径探测，
  与 App 显示名完全解耦。
- 配置迁移现在按「上游 Antigravity Bridge → 更早的 Antigravity Proxy」的顺序查找，
  两条旧路径都能自动迁移。

### 变更

- 应用名称由 Antigravity Bridge 改为 AG Bridge。
- Bundle ID 由 `com.tinybye.antigravity-bridge` 改为 `io.github.a916791360.ag-bridge`。
- 配置目录由 `~/Library/Application Support/Antigravity Bridge/` 改为
  `~/Library/Application Support/AG Bridge/`（旧配置自动迁移，不删除原目录）。
- 发布产物更名为 `AG-Bridge-v<版本>-unsigned.zip` 与 `.dmg`。
- 用户可见文案中的「Antigravity IDE」限定词改为「Antigravity」。

### 安全与分发说明

- v1.0.0 二进制使用 ad-hoc 签名，尚未经过 Apple Developer ID 签名或 Apple 公证。

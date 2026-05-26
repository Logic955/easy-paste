# Easy Paste

<p>
  <a href="./README.md">English</a> |
  <strong>简体中文</strong>
</p>

Easy Paste 是一个原生 macOS 剪贴板工具，目标是做出接近 Paste 的丝滑体验：复制后快速入列，面板快速呼出，选择后稳定粘贴。

## 对用户

### 系统要求

- macOS 13.0 或更高版本。
- Universal App：同时支持 Intel 和 Apple Silicon Mac。

### 安装

打开安装包：

```text
dist/EasyPaste-installer.pkg
```

按安装器提示操作，Easy Paste 会被安装到 `/Applications`。

### 权限

Easy Paste 需要 macOS「辅助功能」权限，用于全局快捷键兜底监听，以及把 `Command + V` 发送回当前应用。

```text
系统设置 -> 隐私与安全性 -> 辅助功能 -> Easy Paste
```

### 主要功能

- 记录文本、链接、富文本和图片剪贴板历史。
- Paste 风格底部面板：玻璃背板、横向卡片、搜索、Pinboard 分组。
- 面板首帧轻量渲染，图片、应用图标、富文本预览异步补齐。
- 快速粘贴：`Command + Shift + V`、`Command + 1...9`、`Command + Shift + 1...9`。
- 按住 `Shift` 进入纯文本粘贴模式。
- 来源提供 RTF / HTML 时，原样粘贴会保留富文本格式。
- 图片卡片展示尺寸和大小。

## 对开发者

### 运行

```bash
swift run EasyPaste
swift run EasyPaste -- --show-on-launch
swift run EasyPaste -- --debug-performance --show-on-launch
```

性能日志：

```text
~/Library/Application Support/EasyPaste/performance.log
```

### 测试

```bash
swift test
```

### 打包

```bash
./scripts/build_app.sh
```

输出：

```text
dist/EasyPaste.app
dist/EasyPaste-installer.pkg
```

发布前验证 Universal 架构：

```bash
lipo -info dist/EasyPaste.app/Contents/MacOS/EasyPaste
```

预期架构：`x86_64 arm64`。

### 存储

```text
~/Library/Application Support/EasyPaste/
```

- `EasyPaste.sqlite`：列表、搜索、设置等元信息。
- `Blobs/`：图片、RTF、HTML 等较大内容。

## TODO

- 格式化输出 / 格式化粘贴工作流：支持 JSON、XML、YAML、SQL、Markdown、纯文本的低成本单手操作。

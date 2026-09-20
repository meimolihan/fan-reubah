# Fan-Reubah - Universal File Converter & Image Processor

a simple web-based tool for processing images and converting documents with a simple interface

## Features

- [x] File Converter (Keep on adding more formats)
- [x] Dark Mode
- [x] Image → SVG Vectorization (Powered by VTracer)
- [x] Chinese/English Language Switcher (default Chinese, toggle in top navigation)
- [ ] API
- [ ] Background Removal for Images
  
## Quick Start

### 使用 systemd 安装（推荐）
一键安装为 systemd 服务（以 root 运行）：
```bash
git clone https://github.com/meimolihan/fan-reubah.git
cd fan-reubah
bash scripts/install.sh -y -p 8081
```
或远程一键安装（自动从 GitHub Release 下载对应架构的自包含单文件二进制）：
```bash
curl -fsSL https://raw.githubusercontent.com/meimolihan/fan-reubah/main/scripts/install.sh | bash -s -- -p 8081
```
访问地址：`http://<服务器IP>:8081`

> 说明：发布二进制为自包含单文件——页面、静态资源与 vtracer SVG 矢量引擎全部内嵌，安装时无需再单独部署前端资产或安装引擎。

#### 安装目录说明
默认应用目录为 `/var/lib/fan-reubah`（二进制已内嵌全部资源，应用目录仅作工作目录使用；二进制固定安装在 `/usr/local/bin/fan-reubah`）。

- **交互式**（未指定 `-a` 且非 `-y` 时，会提示输入应用目录，直接回车使用默认值）：
```bash
bash scripts/install.sh -p 8081
```
- **免交互指定目录**（其余未指定项使用默认值）：
```bash
bash scripts/install.sh -p 8081 -a /var/lib/fan-reubah -y
```
- **远程管道免交互指定目录**：
```bash
curl -fsSL https://raw.githubusercontent.com/meimolihan/fan-reubah/main/scripts/install.sh | bash -s -- -p 8081 -a /var/lib/fan-reubah
```

安装记录写入 `/etc/fan-reubah.conf`，重装/升级会自动沿用上次的端口与应用目录。

常用 systemctl 命令：
```bash
systemctl status fan-reubah        # 查看状态
systemctl restart fan-reubah       # 重启服务
systemctl stop fan-reubah          # 停止服务
systemctl enable fan-reubah        # 开机自启
journalctl -u fan-reubah -f        # 跟随日志
journalctl -u fan-reubah -n 50     # 最近日志
```

### 卸载
停止并移除 systemd 服务、自包含二进制（内嵌 SVG 转换引擎 vtracer）、应用目录与安装记录，并撤销安装时开放的防火墙端口。

```bash
bash scripts/uninstall.sh                  # 交互确认卸载（默认保留应用目录）
bash scripts/uninstall.sh -y               # 免确认卸载（保留应用目录）
bash scripts/uninstall.sh -y --purge       # 免确认卸载并删除应用目录
```

或远程一键卸载（无需克隆仓库，以 root 运行）：
```bash
curl -fsSL https://raw.githubusercontent.com/meimolihan/fan-reubah/main/scripts/uninstall.sh | sudo bash -s -- -y --purge
```

| 参数 | 说明 |
| --- | --- |
| `-y` / `--yes` | 免确认，自动同意卸载 |
| `--purge` / `--delete-appdir` / `--delete-data` | 卸载时同时删除应用目录 |
| `--keep-appdir` / `--keep-data` | 保留应用目录（非交互模式下默认即保留） |
| `-q` / `--quiet` | 静默模式，仅输出关键信息 |

脚本会自动按 `/proc` 终止残留的 fan-reubah 进程，并关闭 install.sh 开放过的防火墙端口（firewalld/ufw/iptables）。

### Using Docker
```bash
git clone https://github.com/meimolihan/fan-reubah.git
cd fan-reubah
docker compose build --no-cache && docker compose up -d
```
or create a folder for the project and run
```bash
docker run -d --name fan-reubah -p 8081:8081 -v doc-temp:/tmp -e PORT=8081 --restart unless-stopped mobufan/fan-reubah:latest
```
Access at: `http://localhost:8081`

### Local Development
Requirements:
- Go 1.22+
- LibreOffice (for document conversion)
- GCC/G++ + libwebp/libheif 开发库
- Rust (cargo) — 可选，用于将 vtracer SVG 引擎内嵌进二进制
- Node.js — 可选，用于构建前端产物

准备内嵌资源（前端 + vtracer 引擎）：
```bash
bash scripts/prepare-embed.sh   # 前端资源 + vtracer 引擎写入 go:embed 目录
```

```bash
go mod download
cd templates && npm install && npm run build && cd ..
bash scripts/prepare-embed.sh
go run cmd/server/main.go
```

### 构建与发布
构建前端产物与 Go 二进制（含 tag 与 GitHub Release）：
```bash
bash scripts/build-and-push.sh v1.0.0 --yes
```

## 项目源码结构说明

### 目录结构

```text
fan-reubah/
├── cmd/                          # Go 可执行程序入口
│   └── server/                   # 主服务（编译为单个自包含二进制）
│       ├── main.go               # 入口：CLI 子命令分发 + HTTP 路由注册
│       ├── cli_status.go         # status 子命令：运行状态 / 内嵌引擎检测
│       ├── cli_uninstall.go      # uninstall 子命令：卸载 systemd 服务与文件
│       └── cli_ui.go             # CLI 输出：彩色文本 / y-n 确认 / 容量格式化
├── internal/                     # 内部包（仅限本项目使用）
│   ├── assets/                   # go:embed 内嵌资源
│   │   ├── assets.go             # 内嵌 web(前端) 与 engine(vtracer)
│   │   ├── web/KEEP              # 前端占位文件（templates/static 由脚本生成）
│   │   └── engine/KEEP           # 引擎占位文件（vtracer_linux_<arch> 由脚本生成）
│   ├── constants/                # 全局常量：大小/尺寸限制、默认值
│   ├── handlers/                 # HTTP 处理器（路由 → 服务）
│   ├── processor/                # 图像 / 文档处理核心
│   │   ├── background/           # 背景去除（泛洪填充）
│   │   ├── document/             # LibreOffice 文档转换 + 图片合并 PDF
│   │   ├── optimize/             # JPEG / PNG / WebP 质量优化
│   │   └── resize/               # 图片缩放（fit / fill / stretch）
│   ├── validator/                # MIME 类型与大小/尺寸校验
├── pkg/                          # 可复用包
│   ├── errors/                   # 错误码模型 + 统一 JSON 错误响应
│   └── response/                 # JSON 成功响应助手（预留）
├── templates/                    # 前端源码（页面 + 组件 + JS 源文件）
│   ├── index.html                # 首页外壳，挂载 4 个页面模板
│   ├── pages/                    # 页面级模板（image / document / svg / batch）
│   ├── components/               # 组件级模板（导航 / 标签 / 上传 / 选项面板等）
│   ├── js/                       # 前端交互逻辑源码（接口调用）
│   ├── main.css / main.js        # 入口样式与脚本
│   └── package.json              # npm 构建配置（tailwind 等）
├── static/                       # 前端构建产物（css / js / assets）
├── vtracer/                      # vendored Rust SVG 矢量引擎（fork 源码）
├── scripts/                      # 运维脚本（安装/卸载/内嵌资源/发布）
├── .github/
│   └── workflows/                # CI 工作流
│       └── release.yml           # workflow_dispatch 手动触发（就让脚本调用）：单文件发布 + 多架构 Docker 镜像
├── Dockerfile                    # 多阶段镜像构建（前端 + vtracer + Go + 精简运行时）
├── docker-compose.yml            # 本地 Docker 启动编排
├── go.mod / go.sum               # Go 模块依赖
└── README.md                     # 项目说明
```

> 构建/运行产物（不入库）：`bin/`（发布二进制）、根目录 `server`、`tmp/`（运行日志）、
> `static/css|js` 与 `internal/assets/{web,engine}` 下的生成内容（均由脚本或 CI 生成，见 `.gitignore`）。

### Go 源码文件说明

| 文件 | 包 | 职责说明 | 关键导出 / 路由 |
| --- | --- | --- | --- |
| `cmd/server/main.go` | main | 程序入口；CLI 子命令分发（`status` / `uninstall` / `-v`）；HTTP 路由注册；静态资源用内嵌 FS、缺失时回退磁盘 `static/` | `main()`、`setupRouter()`、`staticServer()` |
| `cmd/server/cli_status.go` | main | `fan-reubah status`：检测安装记录、当前二进制、内嵌 SVG 引擎、systemd 服务状态 | `rbStatus()` |
| `cmd/server/cli_uninstall.go` | main | `fan-reubah uninstall`：停止/移除 systemd 服务、容器、防火墙端口与安装记录 | `rbUninstall()` |
| `cmd/server/cli_ui.go` | main | CLI 界面工具：ANSI 彩色输出、y/n 确认、人类可读容量格式化 | `cliErr()`、`cliDone()`、`cliConfirm()` 等 |
| `internal/assets/assets.go` | assets | 通过 `//go:embed web engine` 把前端页面、静态资源和 vtracer 引擎内嵌进二进制；按当前平台取对应引擎 | `Web()`、`VtracerBinary()`、`HasVtracer()` |
| `internal/constants/constants.go` | constants | 上传大小限制、图片最大尺寸与默认转换参数 | `MaxFileSize`、`MaxImageWidth/Height`、`Default*` |
| `internal/handlers/handlers.go` | handlers | 加载模板（内嵌 FS 优先、磁盘回退）并渲染首页；通用响应辅助 | `GET /`、`parseTemplates()` |
| `internal/handlers/process.go` | handlers | 图片转换主接口：接收上传 → 校验 → 交给 processor 处理 → 返回结果 | `POST /process` |
| `internal/handlers/svg.go` | handlers | 图片 → SVG 矢量转换接口（预设如海报/示意 + 颜色数/去背景等参数） | `POST /process/svg` |
| `internal/handlers/merge_pdf.go` | handlers | 多张图片合并为一个 PDF 接口 | `POST /process/merge-pdf` |
| `internal/handlers/document.go` | handlers | 文档（docx/doc/odt/rtf/txt ↔ pdf 等）格式转换接口 | `POST /process/document` |
| `internal/processor/processor.go` | processor | 本次转换流程编排：解码 → MIME 验证 → 缩放 → 背景去除 → 质量优化 → 编码 | `ProcessImage()`（包内部） |
| `internal/processor/icon.go` | processor | 向 `image` 包注册 ICNS 解码格式；ICO 编码（BMP/PNG 两套） | `DecodeIcns()` |
| `internal/processor/svg.go` | processor | 组装 vtracer CLI 参数生成 SVG；携带内嵌引擎时自动解压到系统缓存目录执行 | `ResolveVTracer()`、`extractVTracer()` |
| `internal/processor/background/remove.go` | background | 基于色块边界统计 + 泛洪填充的背景去除算法 | `RemoveBackground()` |
| `internal/processor/document/converter.go` | document | 通过 LibreOffice `soffice` 命令完成文档格式转换 | `ConvertDocument()`、`IsFormatSupported()` |
| `internal/processor/document/merge_pdf.go` | document | 将图片合成为单页 PDF（go-fpdf） | `MergeToPDF()` |
| `internal/processor/optimize/optimize.go` | optimize | 按质量等级优化 JPEG/PNG/WebP（调色板、量化等） | `Optimize()`、`GetOptionsForQuality()` |
| `internal/processor/resize/resize.go` | resize | 三种缩放策略：`fit`（等比） / `fill`（裁剪） / `stretch`（拉伸） | `Resize()`、`ParseResizeMode()` |
| `internal/validator/mime.go` | validator | 嗅探 MIME 类型；对 HEIC/HEIF/ICNS 做魔数识别兜底 | `ValidateMIMEType()` |
| `internal/validator/size.go` | validator | 文件大小 / 图片尺寸校验（预留接口，未接入） | `ValidateFileSize()`、`ValidateImageDimensions()` |
| `pkg/errors/errors.go` | errors | 错误码枚举、`AppError` 结构、`SendError` 统一 JSON 错误响应 | `New()`、`SendError()` |
| `pkg/response/json.go` | response | JSON 成功响应助手（`JSON`/`NoContent`/`Created`，预留未接入） | — |

### 运维脚本

| 脚本 | 用途 |
| --- | --- |
| `scripts/install.sh` | systemd 一键安装/升级：部署仓库内或远程 Release 的自包含二进制，写入 `/etc/fan-reubah.conf` 记录，开放防火墙端口，自动补齐缺失运行库 |
| `scripts/uninstall.sh` | 停止并移除 systemd 服务、二进制、应用目录与安装记录；支持 `-y` / `--purge` / `--keep-appdir` / `-q` |
| `scripts/prepare-embed.sh` | 生成 go:embed 内嵌资源：复制前端（剔除 `node_modules`）并把 vtracer 编译产物写入 `internal/assets`（缺失且无 cargo 时仅告警） |
| `scripts/build-and-push.sh` | 发布辅助：递增版本号、提交并推送 `v*` tag，触发 `.github/workflows/release.yml` 完成构建与 Release |

### CI 与基础设施

| 文件 | 说明 |
| --- | --- |
| `.github/workflows/release.yml` | `build-and-push.sh` 调用（`workflow_dispatch` 传 tag）触发：Node 构建前端 + cargo 按 amd64/arm64 交叉编译 vtracer + Go 交叉编译 → 产出 2 个自包含单文件（`fan-reubah_linux_{amd64,arm64}`）并创建 Release → 随后 buildx 多架构构建推送 Docker 镜像至 Docker Hub / GHCR，并同步 CNB 镜像仓库（`linux/amd64`、`linux/arm64`） |
| `Dockerfile` | 多阶段构建：`frontend`（npm 构建）→ `vtracer`（cargo 编译）→ `builder`（写入 go:embed 目录后编译单文件）→ 运行时镜像仅含二进制 + LibreOffice |
| `docker-compose.yml` | 本地一键启动（8081:8081），内置代理环境变量注释示例（按需启用） |

### 前端源码

| 目录/文件 | 说明 |
| --- | --- |
| `templates/index.html` | 首页外壳，通过 `{{ template "page-*" . }}` 挂载 4 个页面 |
| `templates/pages/` | 页面级模板：`image.html` / `document.html` / `svg.html` / `batch.html` |
| `templates/components/` | 组件级模板：`nav` / `tabs` / `upload` / `options-panel` / `progress-result` / `batch-upload` / `document-conversion` / `svg-conversion` |
| `templates/js/` | 前端交互逻辑源码（经构建后以 `/static/js/*.js` 被页面引用：表单提交、接口调用、预览） |
| `templates/package.json` | tailwind 等构建配置；`npm run build` 产物输出到 `static/` |
| `static/` | 构建产物（`css/`、`js/`、`assets/`），由 `prepare-embed.sh` 内嵌进二进制 |

## Images

Here are some images related to the project:

![Home](static/assets/home.png)
![Document Processing](static/assets/document.png)
![Merge](static/assets/merge.png)
![SVG](static/assets/svg.png)
## Format Support & Compatibility

> **Matrix Guide:**
> - Find your source format in the left column
> - Follow the row to find available output formats
> - ✅ = Supported conversion
> - `-` = Same format (no conversion needed)

### Image Conversion Matrix

| From ➡️ To ⬇️ | JPG/JPEG | PNG | WebP | GIF | BMP | HEIC/HEIF | PDF |
|--------------|:---:|:---:|:----:|:---:|:---:|:---:| :---: |
| **JPG/JPEG** | -   | ✅  | ✅   | ✅  | ✅ | ❌ | ✅   |
| **PNG**      | ✅  | -   | ✅   | ✅  | ✅  | ❌ | ✅  |
| **WebP**     | ✅  | ✅  | -    | ✅  | ✅  | ❌ | ✅  |
| **GIF**      | ✅  | ✅  | ✅   | -   | ✅  | ❌ | ✅  |
| **BMP**      | ✅  | ✅  | ✅   | ✅  | -   | ❌| ✅   |
| **HEIC/HEIF**| ✅  | ✅  | ✅   | ✅  | ✅  | - | ✅   |

### Document Conversion Matrix

| From ➡️ To ⬇️ | PDF | DOCX | DOC | ODT | RTF | TXT |
|--------------|:---:|:----:|:---:|:---:|:---:|:---:|
| **PDF** (from PDF currently still bad)     | -   | ✅   | ✅  | ❌  | ❌  | ❌  |
| **DOCX**     | ✅  | -    | ✅  | ✅  | ✅  | ✅  |
| **DOC**      | ✅  | ✅   | -   | ✅  | ✅  | ✅  |
| **ODT**      | ✅  | ✅   | ✅  | -   | ✅  | ✅  |
| **RTF**      | ✅  | ✅   | ✅  | ✅  | -   | ✅  |
| **TXT**      | ✅  | ✅   | ✅  | ✅  | ✅  | -   |

### Additional Image Features

| Format | Background Removal (Soon) | Optimization | Batch Processing |
|--------|:-----------------:|:------------:|:---------------:|
| JPG/JPEG | ❌              | ✅           | ✅              |
| PNG    | ❌                | ❌           | ✅              |
| WebP   | ❌                | ❌           | ✅              |
| GIF    | ❌                | ❌           | ✅              |
| BMP    | ❌                | ❌           | ✅              |
| HEIC/HEIF | ❌             | ❌           | ✅              |

## Notes

- Isolated processing environment
- No file storage - immediate delivery
- Automatic cleanup
- Input validation

## License
This project is licensed under the [MIT License](LICENSE).
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
或远程一键安装（自动从 GitHub Release 下载二进制）：
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/meimolihan/fan-reubah/main/scripts/install.sh)" -- -p 8081
```
访问地址：`http://<服务器IP>:8081`

常用 systemctl 命令：
```bash
systemctl status fan-reubah        # 查看状态
systemctl restart fan-reubah       # 重启服务
systemctl stop fan-reubah          # 停止服务
systemctl enable fan-reubah        # 开机自启
journalctl -u fan-reubah -f        # 跟随日志
journalctl -u fan-reubah -n 50     # 最近日志
```

卸载：
```bash
bash scripts/uninstall.sh -y            # 免确认卸载（保留应用目录）
bash scripts/uninstall.sh -y --purge    # 免确认卸载并删除应用目录
```

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
- Rust (cargo) — 可选，仅 SVG 矢量化功能需要，然后运行 `bash scripts/build-vtracer.sh`

```bash
go mod download
cd templates && npm install && npm run build && cd ..
go run cmd/server/main.go
```

### 构建与发布
构建前端产物与 Go 二进制（含 tag 与 GitHub Release）：
```bash
bash scripts/build-and-push.sh v1.0.0 --yes
```

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
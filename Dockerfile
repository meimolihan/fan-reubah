# ============================================================
# Stage 1: Frontend build (独立阶段，复用 Node 官方基础镜像)
# ============================================================
FROM node:22-alpine AS frontend

WORKDIR /app/templates

# 先只复制依赖清单，命中 Docker 缓存时可跳过 npm ci
COPY templates/package.json templates/package-lock.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci --no-audit --no-fund

# 复制模板源码与静态资源，构建前端产物（输出到 /app/static）
COPY templates/ ./
COPY static/ ../static/
RUN npm run build

# 仅导出运行时需要的产物（剔除 node_modules 等无用内容）
RUN rm -rf node_modules package.json package-lock.json \
    && mkdir -p /out \
    && cp -r ../static /out/static \
    && cp -r . /out/templates

# ============================================================
# Stage 2: VTracer（Rust）矢量化引擎编译
# ============================================================
FROM rust:1.85-alpine AS vtracer

WORKDIR /vtracer

# 使用 vendored 源码，离线可构建（依赖锁在 Cargo.lock）
RUN apk add --no-cache musl-dev gcc
COPY vtracer/ ./
RUN cargo build --release -p vtracer-cli

# ============================================================
# Stage 3: Go 编译（去掉 nodejs/npm，仅保留 cgo 依赖）
# ============================================================
FROM golang:1.22-alpine AS builder

WORKDIR /app

# cgo 编译依赖（前端构建已移至 frontend 阶段）
RUN apk add --no-cache \
    gcc \
    g++ \
    pkgconfig \
    musl-dev \
    libwebp-dev \
    libheif-dev \
    x265-dev \
    libde265-dev

# 先复制 go.mod/go.sum，命中缓存时复用依赖层
COPY go.mod go.sum ./
RUN go mod download

# 复制应用源码并编译（go build 缓存挂载，增量编译更高效）
COPY . ./
RUN --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=1 go build -ldflags="-s -w" -o fan-reubah ./cmd/server

# ============================================================
# Stage 4: 运行时（libreoffice 转换文档、curl 用于健康检查）
# ============================================================
FROM alpine:3.19

WORKDIR /app

# 移除 openjdk11-jre（headless 的 soffice 转换无需 JRE，体积/安装时间大减）
RUN apk add --no-cache \
    bash \
    ttf-liberation \
    libwebp \
    curl \
    libheif \
    x265 \
    libde265 \
    libreoffice \
 && mkdir -p /tmp/.cache /tmp/.config /tmp/.local

# 复制二进制、vtracer 引擎与前端产物
COPY --from=builder /app/fan-reubah /app/fan-reubah
COPY --from=vtracer /vtracer/target/release/vtracer /usr/local/bin/vtracer
COPY --from=frontend /out/static ./static
COPY --from=frontend /out/templates ./templates

# 创建非 root 用户
RUN addgroup -g 1000 appgroup && \
    adduser -u 1000 -G appgroup -D appuser && \
    chown -R appuser:appgroup /app /tmp/.cache /tmp/.config /tmp/.local

USER appuser

# LibreOffice 临时目录
ENV HOME=/tmp

EXPOSE 8081

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s \
  CMD curl -f http://localhost:8081/ || exit 1

CMD ["/app/fan-reubah"]
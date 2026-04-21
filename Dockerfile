FROM ghcr.io/openclaw/openclaw:latest

USER root

# 1. 安裝系統依賴 (wget 和 bzip2 為 Miniconda 安裝必備)
RUN apt-get update && apt-get install -y \
    wget \
    bzip2 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 2. 根據目前系統架構 (x86_64 或 ARM64) 自動下載並安裝最新的 Miniconda
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
        MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"; \
    elif [ "$ARCH" = "aarch64" ]; then \
        MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-aarch64.sh"; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    wget $MINICONDA_URL -O /tmp/miniconda.sh && \
    bash /tmp/miniconda.sh -b -p /opt/conda && \
    rm /tmp/miniconda.sh

# 3. 匯出 conda 執行檔目錄到 PATH
ENV PATH="/opt/conda/bin:$PATH"

# 4. 把 conda 資料夾的權限交給 node，這樣你從終端機進去才能快樂地安裝套件
RUN chown -R node:node /opt/conda

USER node

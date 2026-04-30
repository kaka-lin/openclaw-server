FROM ghcr.io/openclaw/openclaw:latest

USER root

# ==============================================================================
# 💡 為什麼要客製化這個 Dockerfile 並安裝 Python？
# 官方的 ghcr.io/openclaw/openclaw 映像檔是純 Node.js 環境，不包含 Python。
# 但是我們掛載進來的擴充技能 (Skills) 中，可能會有基於 Python 撰寫的 Script
# 為了讓 OpenClaw 能夠在容器內順利呼叫這些工具，我們必須手動安裝 Miniconda，
# 提供 Python 執行環境，並將權限開放給 `node` 使用者，方便日後透過 pip 裝套件。
# ==============================================================================
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

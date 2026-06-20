# Dockerfile — cc-sandbox (Ubuntu 24.04 + Ollama)
# 「サンドボックスで安全に始めるローカルAI入門」実践編 第7章 対応
#
# CPU 経路で動作する最小構成。GPU パススルーは扱わない。

FROM ubuntu:24.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       curl \
       ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Ollama をインストール
RUN curl -fsSL https://ollama.com/install.sh | sh

EXPOSE 11434

# Ollama サーバをフォアグラウンドで起動
CMD ["ollama", "serve"]

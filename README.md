# Local AI Sandbox Kit

**『サンドボックスで安全に始めるローカルAI入門』** companion repository

書籍で組み上げた「安全なローカルAIサンドボックス」の **検証ツール・参照構成・環境ゲート** を配布します。

## 対象読者

本書（概念編 + 実践編 Windows / Mac / Linux のいずれか）の読者。

## リポジトリ構成

```
.
├── scripts/           環境適性ゲート＋サイジング計測
│   ├── preflight.ps1    Windows (PowerShell)
│   ├── preflight.sh     Linux (Bash)
│   ├── preflight.zsh    macOS (Zsh)
│   └── sizing-bench.sh  CPU推論サイジング計測
├── probe-kit/         検証プローブ
│   ├── probe.sh         最小 4 テスト（第4章）
│   └── probe-full.sh    拡張 12 テスト（7原則フルカバー）
├── sandbox/           参照構成（第6章）
│   ├── docker-compose.yml
│   ├── Dockerfile
│   └── .devcontainer/
│       └── devcontainer.json
├── README.md
└── LICENSE
```

| フォルダ | 内容 | 対応章 |
|---------|------|--------|
| `scripts/` | 環境ゲート（preflight）＋サイジング計測（sizing-bench） | 第1章の前・第5章〜 |
| `probe-kit/` | 箱の隔離・権限・ネットワークを検証するプローブ | 第4章・第6章 |
| `sandbox/` | docker-compose + devcontainer の参照構成 | 第6章 |

## 使い方

### 1. 環境適性を確認する（第1章の前に）

自分の PC が本書の手順を通せるかを確認します。

**Windows (PowerShell):**
```powershell
powershell -ExecutionPolicy Bypass -File scripts/preflight.ps1
```

**Linux:**
```bash
bash scripts/preflight.sh
```

**macOS:**
```zsh
zsh scripts/preflight.zsh
```

出力の `verdict` が `PASS` なら問題ありません。`WARN` の場合は注記を確認してください。

### 2. 検証プローブを実行する（第4章）

第4章で手打ちした 4 つのコマンドをスクリプト化したものです。箱（コンテナ）が隔離されているかを一括チェックします。

```bash
# 最小プローブ（4テスト）
bash probe-kit/probe.sh cc-sandbox

# 拡張プローブ（12テスト・7原則フルカバー）
bash probe-kit/probe-full.sh cc-sandbox
```

引数を省略すると `cc-sandbox` を対象にします。

### 3. 参照構成を使う（第6章）

`sandbox/` は、第6章で CC（Claude Code）に生成させた構成の **参照実装** です。

```bash
cd sandbox
docker compose up -d
```

起動後、ブラウザで `http://localhost:3000` を開けば Open WebUI が表示されます。

初回はモデルの pull が必要です:
```bash
docker compose exec ollama ollama pull llama3.2:1b
```

VS Code の Dev Containers で「Reopen in Container」すれば、CC ごと箱の中に入れます（第6章 §7.3）。

### 4. サイジングを計測する（第5章〜）

自分の環境で各モデルの生成速度（tok/s）とメモリ使用量を計測します。cc-sandbox 内で Ollama が起動済みであることが前提です。

```bash
docker cp scripts/sizing-bench.sh cc-sandbox:/tmp/
docker exec cc-sandbox bash /tmp/sizing-bench.sh
```

第6章で devcontainer を組んだあとなら、箱の中の CC に「sizing-bench.sh を使ってモデルを計測して」と頼むだけで済みます。

デフォルトでは `llama3.2:1b`, `llama3.2:3b`, `gemma3:4b`, `llama3.1:8b` の4モデルを順に計測します。引数でモデルを指定することもできます:

```bash
docker exec cc-sandbox bash /tmp/sizing-bench.sh llama3.2:1b phi4-mini
```

#### 参考値（著者環境）

モデルのバージョンアップで数値は変わるため、あくまで特定時点での参考値です。自分の環境では `sizing-bench.sh` を実行して確認してください。

**Apple Silicon Mac — M1 MacBook Pro 16GB / macOS Tahoe / Docker Desktop（2026-06-28）**

| model | params | tok/s | tokens | model\_mem |
|-------|--------|------:|-------:|-----------:|
| llama3.2:1b | 1B | 20.4 | 87 | 1,715 MB |
| llama3.2:3b | 3B | 15.7 | 84 | 2,751 MB |
| gemma3:4b | 4B | 12.2 | 73 | 3,273 MB |
| llama3.1:8b | 8B | 7.7 | 96 | 5,317 MB |

> コンテナ可視メモリ 8GB・CPU 推論。8GB コンテナでは llama3.1:8b（5.3GB）が実用上限に近く、インタラクティブ用途なら 3B〜4B あたりが速度とメモリのバランス点。

<!-- sizing-results: Windows (evo-x1) / Linux 計測後に追加 -->

## 動作確認の範囲について

このリポジトリのスクリプト（`scripts/`・`probe-kit/`）および参照構成（`sandbox/`）は、**本書の説明で使用する限定的な環境で動作を確認したもの**です。すべての OS バージョン、Docker バージョン、コンテナ構成、ネットワーク環境において正しい結果を返すことを保証するものではありません。

特に `probe-kit/` の検証プローブは、本書が扱う標準構成（Ubuntu 24.04 ベースの Docker コンテナ、Docker Desktop on WSL2）を前提としています。異なる構成で実行した場合、偽陽性（問題がないのに FAIL と判定される）や偽陰性（問題があるのに PASS と判定される）が生じる可能性があります。プローブの結果は、セキュリティ上の判断の**参考情報**として扱い、唯一の根拠としないでください。

問題を発見した場合は [Issues](../../issues) で報告いただけると助かります。

## sandbox/ は「答え」ではありません

このリポジトリの `sandbox/` は、書籍の手順で到達する構成の **参照** です。

本書の価値は「CC に作らせ、自分で査読し、検証する」プロセスにあります。ファイルをコピーして動かすだけでは、**なぜその設定なのか** が身につきません。まず本文の手順を自分で通し、行き詰まったときの照合先としてこのリポジトリを使ってください。

## GUI・画面表示の差異について

Docker Desktop、VS Code、Open WebUI などの GUI は、バージョンアップに伴い本文のスクリーンショットと異なる場合があります。コマンドや設定ファイルの内容が変わった場合は、このリポジトリの [Issues](../../issues) で正誤・追従情報を提供します。

## ライセンス

- **スクリプト・設定ファイル** (`scripts/`, `probe-kit/`, `sandbox/`): [MIT License](LICENSE)
- **ドキュメント** (`README.md` 等のテキスト): [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)

詳細は [LICENSE](LICENSE) を参照してください。

## 書籍情報

- **書名:** サンドボックスで安全に始めるローカルAI入門
- **シリーズ:** AI Engineering Series
- **著者:** Manabazu
- **出版:** Manabazu舎

#!/bin/zsh
# One-time setup on macOS (Apple Silicon recommended):
#   1. builds whisper.cpp (Metal) into vendor/whisper.cpp
#   2. downloads a Whisper model into models/   (skipped with --model-path)
#   3. creates .venv and installs Python packages
#   4. creates config.env from config.example.env
# Usage:
#   scripts/setup-mac.sh                       # model large-v3 (~3.1 GB, best for Korean)
#   scripts/setup-mac.sh --model large-v3-turbo  # ~1.6 GB, faster, slightly less accurate
#   scripts/setup-mac.sh --model-path ~/models/ggml-large-v3.bin   # use a model you already have
# If the compiler check fails with "tapi error" / "unknown architecture", your default SDK doesn't match
# your toolchain. Pick another one: MACOS_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk scripts/setup-mac.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
WHISPER_TAG="${WHISPER_TAG:-v1.8.4}"
MODEL="large-v3"
MODEL_PATH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL="$2"; shift 2 ;;
    --model-path) MODEL_PATH="$2"; shift 2 ;;
    *) echo "알 수 없는 옵션: $1"; exit 1 ;;
  esac
done

say() { print -P "%F{green}==>%f $1"; }
need() { command -v "$1" >/dev/null || { echo "$1 이(가) 필요합니다. $2"; exit 1; }; }

xcode-select -p >/dev/null 2>&1 || { echo "Xcode Command Line Tools가 필요합니다: xcode-select --install"; exit 1; }
need git "xcode-select --install"
need cmake "brew install cmake"
PY=""
for c in python3.13 python3.12 python3.11 python3.10 python3; do
  if command -v $c >/dev/null && $c -c 'import sys; sys.exit(sys.version_info < (3, 10))' 2>/dev/null; then PY=$(command -v $c); break; fi
done
[[ -n "$PY" ]] || { echo "Python 3.10 이상이 필요합니다: brew install python@3.12"; exit 1; }

say "whisper.cpp $WHISPER_TAG 빌드 (Metal)"
if [[ ! -d vendor/whisper.cpp ]]; then
  mkdir -p vendor
  git clone --depth 1 --branch "$WHISPER_TAG" https://github.com/ggml-org/whisper.cpp vendor/whisper.cpp
fi
SDK_ARGS=()
if [[ -n "${MACOS_SDK:-}" ]]; then export SDKROOT="$MACOS_SDK"; SDK_ARGS=(-DCMAKE_OSX_SYSROOT="$MACOS_SDK"); fi
cmake -S vendor/whisper.cpp -B vendor/whisper.cpp/build -DCMAKE_BUILD_TYPE=Release -DGGML_METAL=ON \
      -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=ON "${SDK_ARGS[@]}" >/dev/null
cmake --build vendor/whisper.cpp/build --config Release -j --target whisper-server
[[ -x vendor/whisper.cpp/build/bin/whisper-server ]] || { echo "whisper-server 빌드 결과가 없습니다."; exit 1; }

if [[ -n "$MODEL_PATH" ]]; then
  MODEL_FILE="${MODEL_PATH/#\~/$HOME}"
  [[ -f "$MODEL_FILE" ]] || { echo "모델 파일이 없습니다: $MODEL_FILE"; exit 1; }
  say "기존 모델 사용: $MODEL_FILE"
else
  MODEL_FILE="models/ggml-$MODEL.bin"
  if [[ ! -f "$MODEL_FILE" ]]; then
    say "Whisper 모델 다운로드: ggml-$MODEL.bin (Hugging Face ggerganov/whisper.cpp)"
    mkdir -p models
    curl -L --fail --progress-bar -o "$MODEL_FILE.part" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$MODEL.bin"
    mv "$MODEL_FILE.part" "$MODEL_FILE"
  fi
fi

say "Python 가상환경 (.venv, $($PY --version))"
[[ -x .venv/bin/python ]] || "$PY" -m venv .venv
.venv/bin/python -m pip install --quiet --upgrade pip
.venv/bin/python -m pip install --quiet -r requirements.txt

if [[ ! -f config.env ]]; then cp config.example.env config.env; fi
# Point config.env at the model chosen above.
sed -i '' -e "s|^GQAI_WHISPER_MODEL=.*|GQAI_WHISPER_MODEL=$MODEL_FILE|" config.env

say "완료"
echo "  Claude 인증: 이미 Claude Code에 로그인했다면 그대로 됩니다. 아니면 scripts/claude-login.sh 또는 config.env의 ANTHROPIC_API_KEY"
echo "  브라우저로 쓰기: scripts/run.sh"
echo "  Mac 앱 만들기:  mac/build.sh"

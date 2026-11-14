# GQAI Live

말하면 바로 글이 되는 macOS용 개인 받아쓰기 도구입니다.

1. 내 목소리를 **이 Mac에서** Whisper(whisper.cpp)로 실시간 전사하고
2. 말을 멈추면 **Claude**가 군말을 지우고 문장을 다듬은 뒤
3. (Mac 앱) 녹음을 끝내면 **지금 쓰던 앱의 입력창**(Claude, ChatGPT, Slack, 메일 …)에 바로 붙여 넣습니다.

```
⌥⇧R 누르고 말하기 ─▶ Whisper (로컬) ─▶ Claude 정리 ─▶ ⌥⇧R 다시 누르면 앞 앱 입력창에 붙여 넣기
```

> 완성된 앱을 배포하는 프로젝트가 아닙니다. **소스를 받아 각자 빌드해서 쓰는** 개인용 도구입니다.
> 원작자가 쓰던 앱에서 이 기능만 떼어 냈습니다. 빠진 기능은 [docs/FEATURES-NOT-INCLUDED.md](docs/FEATURES-NOT-INCLUDED.md),
> Windows에서 만드는 방법은 [docs/WINDOWS.md](docs/WINDOWS.md)를 보세요.

## 무엇이 어디로 가나요

| 데이터 | 처리 위치 |
|---|---|
| 음성 | **이 Mac 밖으로 나가지 않습니다.** 브라우저/앱 → 로컬 서버(127.0.0.1) → whisper.cpp |
| 전사된 텍스트 | 정리할 때 **Anthropic(Claude)으로 전송**됩니다. "Claude로 정리"를 끄면 보내지 않습니다 |
| 용어 사전 | `data/dictionary.json` (로컬) |
| 기록 | 저장하지 않습니다. 화면을 닫으면 사라집니다(필요하면 복사) |

## 준비물

- macOS 14.2 이상, **Apple Silicon 권장**(Intel Mac은 Whisper가 느립니다)
- Xcode Command Line Tools (`xcode-select --install`), [Homebrew](https://brew.sh)의 `cmake`, Python 3.10+
- Claude 인증 중 하나
  - Claude 계정 로그인: 이미 [Claude Code](https://docs.claude.com/claude-code)를 쓰고 있으면 그대로 됩니다. 아니면 설치 후 `scripts/claude-login.sh`
  - 또는 Anthropic API 키: `config.env`의 `ANTHROPIC_API_KEY` (사용량만큼 과금)
- 디스크: Whisper 모델 약 3GB(`large-v3`) 또는 1.6GB(`large-v3-turbo`)

## 설치

```bash
git clone https://github.com/<you>/gqai-live.git
cd gqai-live
brew install cmake python@3.12        # 없을 때만
scripts/setup-mac.sh                  # whisper.cpp 빌드 + 모델 다운로드 + Python 환경 + config.env
```

옵션
- `scripts/setup-mac.sh --model large-v3-turbo` : 더 작고 빠른 모델
- `scripts/setup-mac.sh --model-path ~/models/ggml-large-v3.bin` : 이미 받은 모델 사용
- 컴파일러 확인 단계에서 `tapi error` / `unknown architecture`가 나면 SDK가 툴체인과 맞지 않는 것입니다:
  `MACOS_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk scripts/setup-mac.sh`

## 쓰기

### A. 브라우저로 (가장 간단)

```bash
scripts/run.sh          # 서버를 띄우고 http://127.0.0.1:7860 을 엽니다. Ctrl+C로 종료
```

시작(또는 ⌥R) → 말하기 → 중지. 원문과 정리된 글이 쌓이고, 복사 버튼으로 가져갑니다.
브라우저에서는 다른 앱에 자동으로 넣을 수 없습니다.

### B. Mac 앱으로 (전역 단축키 + 앞 앱에 넣기)

```bash
mac/build.sh            # ~/Applications/GQAI Live.app 을 만들고 설치
open ~/Applications/"GQAI Live.app"
```

1. 앱 화면에서 **"멈추면 앞 앱 입력창에 바로 넣기"**를 켭니다.
2. macOS가 **손쉬운 사용** 권한을 물으면 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 **GQAI Live**를 켭니다.
   (목록에 없으면 `+`로 `~/Applications/GQAI Live.app`을 추가)
3. 아무 앱의 입력창에 커서를 두고 **⌥⇧R (Option+Shift+R)** → 말하기 → **⌥⇧R**.
   남은 구간을 전사·정리한 뒤 그 입력창에 붙여 넣고, 클립보드는 원래대로 되돌립니다.

- 앱은 이 저장소 폴더의 서버를 실행합니다. **폴더를 옮기면 `mac/build.sh`로 다시 빌드**하세요.
- 창을 닫아도 메뉴 막대에서 계속 동작합니다. 완전히 끄려면 메뉴 막대 아이콘 → 종료.
- 다시 빌드하면 서명이 바뀌어 마이크·손쉬운 사용 권한을 다시 켜야 할 수 있습니다(설정에서 예전 항목을 지우고 다시 추가).
- 단축키를 바꾸려면 `mac/Sources/main.swift`의 `HotKey(keyCode:modifiers:)`를 고칩니다.

### 화면 옵션

| 옵션 | 설명 |
|---|---|
| 말하는 언어 | 자동 감지 / 한국어 / 영어 / 일본어 / 중국어 |
| 정리할 쉼 | 말을 이만큼 멈추면 그때까지의 말을 Claude가 정리 (기본 3초) |
| 정리 언어 | 말한 언어 그대로, 또는 다른 언어로 옮겨 정리 |
| Claude로 정리 | 끄면 원문만 (넣기도 원문) |
| 용어 사전 | 이름·약어·전문용어. Whisper 인식 힌트와 Claude 표기에 함께 쓰임 |

정리는 **말투를 그대로 두고** 군말·반복·고쳐 말한 흔적만 지우며 마크다운을 쓰지 않습니다(프롬프트 입력용).
규칙은 `server/organizer.py`의 `SYSTEM_PROMPT`에 있습니다.

## 설정 (`config.env`)

`config.example.env`를 복사해 만듭니다(설치 스크립트가 해 줌). 같은 이름의 환경 변수가 있으면 그쪽이 우선합니다.

| 키 | 기본값 | 설명 |
|---|---|---|
| `GQAI_PORT` | 7860 | 로컬 웹 서버 포트. 바꾸면 Mac 앱도 다시 빌드 |
| `GQAI_WHISPER_BIN_DIR` | `vendor/whisper.cpp/build/bin` | `whisper-server`가 있는 폴더 |
| `GQAI_WHISPER_MODEL` | `models/ggml-large-v3.bin` | Whisper 모델 파일 |
| `GQAI_WHISPER_PORT` | 8178 | whisper-server 포트 |
| `GQAI_CLAUDE_MODEL` | `claude-sonnet-5-5` | 정리에 쓸 Claude 모델 |
| `GQAI_CLAUDE_EFFORT` | `low` | 추론 강도. 낮을수록 빠름 |
| `ANTHROPIC_API_KEY` | (비움) | 넣으면 API 키로, 비우면 `claude` 로그인으로 |

## 문제 해결

| 증상 | 확인 |
|---|---|
| 상단에 "Whisper 없음" | `scripts/setup-mac.sh`를 다시 실행. 칩에 마우스를 올리면 이유가 보입니다 |
| "Claude 인증 필요" | `scripts/claude-login.sh` 또는 `ANTHROPIC_API_KEY` |
| 앱이 "프로젝트 폴더를 찾을 수 없습니다" | 저장소를 옮겼다면 `mac/build.sh` 다시 실행 |
| 붙여 넣지 않고 "클립보드에 복사만" | 손쉬운 사용 권한. 다시 빌드했다면 예전 항목을 지우고 다시 추가 |
| "앱 창에서 시작해 넣을 앱이 없습니다" | 앱 창의 버튼이 아니라 **⌥⇧R**로 시작해야 앞 앱을 기억합니다 |
| 전사가 느림 | 더 작은 모델(`large-v3-turbo`, `small`)로 `GQAI_WHISPER_MODEL` 변경 |

로그: `~/Library/Logs/GQAILive/` (`server.log`, `whisper-server.log`, `app-server.log`). 전사 원문은 로그에 남기지 않습니다.

## 구조

```
server/   Python 로컬 서버 (표준 라이브러리 + Claude Agent SDK)
  server.py          HTTP 경로, 전사 요청 검증, Whisper 환각 문구 거르기
  whisper_server.py  whisper.cpp whisper-server 실행·요청
  organizer.py       Claude 정리 (녹음마다 세션 하나를 열어 두고 이어 씀)
  dictionary.py      용어 사전
  config.py          config.env / 환경 변수
web/      화면 (index.html, app.js, mic-worklet.js) — 빌드 과정 없음
mac/      Swift 앱 (창, 메뉴 막대, ⌥⇧R, 앞 앱에 넣기) + build.sh
scripts/  setup-mac.sh, run.sh, claude-login.sh
docs/     WINDOWS.md, FEATURES-NOT-INCLUDED.md
```

AI 코딩 도구로 고치거나 기능을 넣을 때는 [AGENTS.md](AGENTS.md)를 먼저 읽게 하세요.

## 라이선스

MIT. whisper.cpp(MIT)와 Whisper 모델(MIT), Claude Agent SDK는 각자의 라이선스와 약관을 따릅니다.
Claude 사용은 [Anthropic 이용 약관](https://www.anthropic.com/legal)을 따릅니다.

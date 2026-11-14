# GQAI Live

말하면 바로 글이 되는 macOS용 개인 받아쓰기 도구입니다.

1. 내 목소리를 **이 Mac에서** Whisper(whisper.cpp)로 실시간 전사하고
2. 말을 멈추면 **Claude**가 군말을 지우고 문장을 다듬은 뒤
3. (Mac 앱) 녹음을 끝내면 **지금 쓰던 앱의 입력창**(Claude, ChatGPT, Slack, 메일 …)에 바로 붙여 넣습니다.
4. (Mac 앱) **지시 모드**: 문서에서 글을 선택하고 ⌃⌥E → "이 문단 간결하게", "내일 서울 날씨 정리해 줘"처럼 말하면,
   Claude가 수행한 결과(필요하면 웹 검색 포함)로 선택한 글을 바꾸거나 그 뒤에 넣습니다.

```
받아쓰기  ⌃⌥R 누르고 말하기 ─▶ Whisper (로컬) ─▶ Claude 정리 ─▶ ⌃⌥R 다시 누르면 앞 앱 입력창에 붙여 넣기
지시      글 선택 ─▶ ⌃⌥E 누르고 지시 말하기 ─▶ ⌃⌥E ─▶ Claude 수행(웹 검색) ─▶ 선택한 글을 바꾸거나 뒤에 넣기
```

> 완성된 앱을 배포하는 프로젝트가 아닙니다. **소스를 받아 각자 빌드해서 쓰는** 개인용 도구입니다.
> 원작자가 쓰던 앱에서 이 기능만 떼어 냈습니다. 빠진 기능은 [docs/FEATURES-NOT-INCLUDED.md](docs/FEATURES-NOT-INCLUDED.md),
> Windows에서 만드는 방법은 [docs/WINDOWS.md](docs/WINDOWS.md)를 보세요.

## 무엇이 어디로 가나요

| 데이터 | 처리 위치 |
|---|---|
| 음성 | **이 Mac 밖으로 나가지 않습니다.** 브라우저/앱 → 로컬 서버(127.0.0.1) → whisper.cpp |
| 전사된 텍스트 | 정리할 때 **Anthropic(Claude)으로 전송**됩니다. "Claude로 정리"를 끄면 보내지 않습니다 |
| 선택한 글 (지시 모드) | ⌃⌥E를 누를 때 앞 앱에서 **선택해 둔 글이 지시와 함께 Anthropic으로 전송**됩니다. 받아쓰기(⌃⌥R)는 선택한 글을 읽지 않습니다 |
| 웹 검색 (지시 모드) | 지시가 최신 정보(날씨, 일정, 뉴스 …)를 요구하면 Claude가 **웹 검색**을 하고, 검색어가 웹 검색으로 나갑니다. 받아쓰기는 검색하지 않습니다 |
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
git clone https://github.com/yongkyu4803/gqai-live.git
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
3. 아무 앱의 입력창에 커서를 두고 **⌃⌥R (Control+Option+R)** → 말하기 → **⌃⌥R**. 시작할 때와 멈출 때 "삑" 소리가 나니 소리 뒤에 말하세요. 지시 모드(⌃⌥E)도 같습니다.
   남은 구간을 전사·정리한 뒤 그 입력창에 붙여 넣고, 클립보드는 원래대로 되돌립니다.

- 앱은 이 저장소 폴더의 서버를 실행합니다. **폴더를 옮기면 `mac/build.sh`로 다시 빌드**하세요.
### C. 지시 모드 (Mac 앱, ⌃⌥E)

받아쓰기가 "말한 대로 옮기기"라면, 지시 모드는 "말로 시키기"입니다.

1. 문서(구글 문서, 메일, 메모 …)에서 참고할 글을 **선택**합니다. 선택하지 않아도 됩니다(커서 자리에 새 글을 씁니다).
2. **⌃⌥E** (Control+Option+E) → **"삑" 소리가 나면** 지시를 말합니다. 소리 전에 말하면 앞부분이 잘립니다.
   예: "이 문단 더 간결하게", "이걸 세 줄로 요약해서 아래에 넣어 줘", "영어로 번역해 줘",
   "팀장님께 보낼 일정 변경 메일 써 줘, 목요일 3시에서 금요일 10시로", "내일 서울 날씨랑 가볼 만한 전시 정리해 줘".
3. **⌃⌥E** 다시 → 끝나는 소리가 나고, Claude가 수행한 결과를 넣습니다. 고치라는 지시면 **선택한 글을 바꾸고**,
   새 글을 더하라는 지시면 **선택한 글 뒤에** 넣습니다. 화면의 "지시 결과를 넣는 곳"에서 한쪽으로 고정할 수 있습니다.
   바뀐 결과가 마음에 들지 않으면 그 앱에서 ⌘Z로 되돌리세요.

- 선택한 글은 앱이 ⌘C로 복사해 읽고, 클립보드는 곧바로 원래대로 되돌립니다(손쉬운 사용 권한 필요).
- 말하는 동안에는 Claude에 보내지 않고, 멈춘 뒤 한 번에 보냅니다. 추론 강도는 `GQAI_COMMAND_EFFORT`(기본 `medium`).
  글을 고치는 지시는 보통 3~8초, 웹 검색이 필요한 지시는 20~40초 걸립니다.
- **웹 검색**: 날씨·일정·뉴스·가격처럼 최신 정보가 필요한 지시에만 Claude가 검색(WebSearch)하고 페이지를 읽습니다(WebFetch).
  검색한 내용을 쓰면 글 끝에 `출처:` 한 줄이 붙습니다. 확인하지 못한 내용은 지어내지 않고 확인하지 못했다고 씁니다.
  켜는 도구는 이 둘뿐이며, 파일 접근·명령 실행 도구는 쓰지 않습니다.
- 지시는 반드시 ⌃⌥E로 시작한 녹음 안에서 말합니다. ⌃⌥R로 말하면 받아쓰기로 처리됩니다.
- 결과는 서식 없는 글로 들어갑니다(제목·굵게 같은 서식은 없음).
- 일부 앱(코드 편집기 등)은 선택이 없을 때 ⌘C로 현재 줄을 복사합니다. 그때는 그 줄이 선택한 글로 쓰입니다.
- 앱 창 안에서는 원문·정리된 글 상자에서 선택하고 **지시** 버튼(⌥E)을 눌러 같은 일을 할 수 있습니다(결과는 화면에만).

### 공통

- 창을 닫아도 메뉴 막대에서 계속 동작합니다. 완전히 끄려면 메뉴 막대 아이콘 → 종료.
- 다시 빌드하면 서명이 바뀌어 마이크·손쉬운 사용 권한을 다시 켜야 할 수 있습니다(설정에서 예전 항목을 지우고 다시 추가).
- 예전 단축키 ⌥⇧R / ⌥⇧E도 함께 등록됩니다.
- 단축키를 바꾸려면 `mac/Sources/main.swift`의 `HotKey(keyCode:modifiers:)`를 고칩니다.
  구글 문서는 ⌃⌥+글자를 메뉴 열기에 쓰지만, 앱이 실행 중이면 ⌃⌥R·⌃⌥E는 앱이 먼저 받습니다.

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
| `GQAI_CLAUDE_EFFORT` | `low` | 받아쓰기 정리의 추론 강도. 낮을수록 빠름 |
| `GQAI_COMMAND_EFFORT` | `medium` | 지시 모드의 추론 강도 |
| `ANTHROPIC_API_KEY` | (비움) | 넣으면 API 키로, 비우면 `claude` 로그인으로 |

## 문제 해결

| 증상 | 확인 |
|---|---|
| 상단에 "Whisper 없음" | `scripts/setup-mac.sh`를 다시 실행. 칩에 마우스를 올리면 이유가 보입니다 |
| "Claude 인증 필요" | `scripts/claude-login.sh` 또는 `ANTHROPIC_API_KEY` |
| 앱이 "프로젝트 폴더를 찾을 수 없습니다" | 저장소를 옮겼다면 `mac/build.sh` 다시 실행 |
| 붙여 넣지 않고 "클립보드에 복사만" | 손쉬운 사용 권한. 다시 빌드했다면 예전 항목을 지우고 다시 추가 |
| "앱 창에서 시작해 넣을 앱이 없습니다" | 앱 창의 버튼이 아니라 **⌃⌥R**(지시는 ⌃⌥E)로 시작해야 앞 앱을 기억합니다 |
| 지시 모드에서 "선택한 글 없음"인데 선택했음 | 그 앱이 ⌘C를 받지 않은 경우입니다. 손쉬운 사용 권한을 확인하고, ⌃⌥E를 짧게 눌렀다 떼세요 |
| 지시했는데 아무것도 안 들어감 | 앱 창의 안내를 보세요. "지시가 인식되지 않았습니다"면 삑 소리 뒤에 또렷하게 다시 말하세요. 웹 검색이 필요한 지시는 30초 넘게 걸릴 수 있습니다 |
| ⌃⌥E를 누르면 글자가 입력되거나 다른 앱 메뉴가 열림 | 앱이 실행 중인지(메뉴 막대 아이콘) 확인하세요. 다른 단축키 앱이 같은 키를 쓰면 `mac/Sources/main.swift`에서 단축키를 바꾸세요 |
| 전사가 느림 | 더 작은 모델(`large-v3-turbo`, `small`)로 `GQAI_WHISPER_MODEL` 변경 |

로그: `~/Library/Logs/GQAILive/` (`server.log`, `whisper-server.log`, `app-server.log`). 전사 원문은 로그에 남기지 않습니다.

## 구조

```
server/   Python 로컬 서버 (표준 라이브러리 + Claude Agent SDK)
  server.py          HTTP 경로, 전사 요청 검증, Whisper 환각 문구 거르기
  whisper_server.py  whisper.cpp whisper-server 실행·요청
  organizer.py       Claude 정리 (녹음마다 세션 하나를 열어 두고 이어 씀), 지시 모드 프롬프트
  dictionary.py      용어 사전
  config.py          config.env / 환경 변수
web/      화면 (index.html, app.js, mic-worklet.js) — 빌드 과정 없음
mac/      Swift 앱 (창, 메뉴 막대, ⌃⌥R·⌃⌥E, 선택 읽기, 앞 앱에 넣기) + build.sh
scripts/  setup-mac.sh, run.sh, claude-login.sh
docs/     WINDOWS.md, FEATURES-NOT-INCLUDED.md
```

AI 코딩 도구로 고치거나 기능을 넣을 때는 [AGENTS.md](AGENTS.md)를 먼저 읽게 하세요.

## 라이선스

MIT. whisper.cpp(MIT)와 Whisper 모델(MIT), Claude Agent SDK는 각자의 라이선스와 약관을 따릅니다.
Claude 사용은 [Anthropic 이용 약관](https://www.anthropic.com/legal)을 따릅니다.

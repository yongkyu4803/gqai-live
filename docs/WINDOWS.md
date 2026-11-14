# Windows에서 GQAI Live 만들기

이 저장소의 소스는 **macOS 전용**입니다. Windows용 코드는 들어 있지 않습니다.
이 문서는 Windows에서 같은 기능(말하기 → 라이브 전사 → Claude 정리 → 앞 앱 입력창에 넣기)을
직접 만들려는 사람을 위해, 원작자가 검토한 내용을 정리한 것입니다.

> 이 문서의 내용은 **Windows 기기에서 검증하지 않았습니다.** 설계 검토 결과입니다.
> 만들어 보고 다른 점이 있으면 이 문서를 고쳐 주세요.

## 1. 결론

- **가능합니다.** 서버(Python)와 웹 화면(`web/`)은 거의 그대로 쓰고,
  Mac의 Swift 앱(`mac/`)에 해당하는 **작은 Windows 앱 하나**만 새로 만들면 됩니다.
- 네이티브 앱 없이도 **브라우저(Chrome·Edge)로 라이브 전사와 정리**까지는 바로 됩니다.
  전역 단축키와 "앞 앱 입력창에 넣기"만 네이티브 앱이 필요합니다.

## 2. 구성 요소별로 보면

| 구성 요소 | Windows에서 | 할 일 |
|---|---|---|
| 웹 화면 `web/` (녹음, 쉼 감지, 16kHz 변환, 정리 표시) | Chrome·Edge·WebView2에서 그대로 동작 | 없음. 앱 연결 코드(`Native`)가 이미 `window.chrome.webview`를 지원합니다 |
| Python 서버 `server/` | 표준 라이브러리 + Claude Agent SDK. 거의 그대로 | `config.py`가 `.exe` 이름과 로그 폴더(`data/logs`)를 이미 처리합니다. 설치 스크립트만 새로 필요 |
| Whisper (whisper.cpp `whisper-server`) | Windows 빌드 지원 | PowerShell 설치 스크립트로 빌드하거나 릴리스 파일을 받음 |
| Claude 정리 (Agent SDK) | Windows 지원 | Claude Code에 로그인하거나 `ANTHROPIC_API_KEY` 사용 |
| 앱 창·트레이·전역 단축키·앞 앱에 넣기 | `mac/`은 Mac 전용 | **Windows 앱을 새로 만듦** (아래 4장) |
| ffmpeg | 필요 없음 | 웹 화면이 16kHz WAV로 바꿔 보냅니다 |

## 3. 브라우저로 먼저 돌려 보기 (네이티브 앱 없이)

1. 준비물: Git, Python 3.10 이상, (빌드한다면) Visual Studio Build Tools 2022 + CMake
2. whisper.cpp 준비 (둘 중 하나)
   - **릴리스 파일 받기:** https://github.com/ggml-org/whisper.cpp/releases 에서
     `whisper-bin-x64.zip`(CPU) 또는 `whisper-cublas-…-bin-x64.zip`(NVIDIA GPU)을 받아
     `vendor\whisper.cpp\build\bin\` 에 풉니다. 안에 `whisper-server.exe`가 있어야 합니다.
     (릴리스마다 파일 이름과 폴더 구조가 다를 수 있으니 확인하세요.)
   - **직접 빌드:**
     ```powershell
     git clone --depth 1 --branch v1.8.4 https://github.com/ggml-org/whisper.cpp vendor\whisper.cpp
     cmake -S vendor\whisper.cpp -B vendor\whisper.cpp\build -DCMAKE_BUILD_TYPE=Release   # NVIDIA: -DGGML_CUDA=ON, 기타 GPU: -DGGML_VULKAN=ON
     cmake --build vendor\whisper.cpp\build --config Release -j --target whisper-server
     ```
     MSVC 빌드는 결과가 `build\bin\Release\`에 생길 수 있습니다. 그때는 `config.env`의
     `GQAI_WHISPER_BIN_DIR`을 그 폴더로 맞춥니다.
3. 모델 받기: `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-<모델>.bin` 을 `models\`에 저장
4. Python 환경:
   ```powershell
   py -3.12 -m venv .venv
   .venv\Scripts\python -m pip install -r requirements.txt
   copy config.example.env config.env      # GQAI_WHISPER_MODEL, GQAI_WHISPER_BIN_DIR 확인
   .venv\Scripts\python server\server.py
   ```
5. Chrome이나 Edge로 `http://127.0.0.1:7860` 을 엽니다.

**모델 고르기.** Windows는 GPU에 따라 속도 차이가 큽니다.

| 환경 | 권장 모델 |
|---|---|
| NVIDIA GPU (CUDA 빌드) | `large-v3` (한국어 정확도 가장 좋음) |
| 다른 GPU (Vulkan 빌드) | `large-v3-turbo` |
| GPU 없음 (CPU) | `small` 또는 `base`. `large-v3`는 라이브로 쓰기에 너무 느림 |

라이브 전사는 말한 구간(최대 20초)을 바로 처리해야 하므로, 구간 하나가 1~2초 안에 끝나는 모델을 고르세요.

## 4. Windows 네이티브 앱 설계

### 4.1 권장 구성: C# (.NET 8) + WinForms + WebView2

Mac 앱(`mac/Sources/*.swift`, 약 500줄)이 하는 일을 그대로 옮기면 됩니다. 예상 분량도 비슷합니다.

| 기능 | Mac (`mac/`) | Windows (새로 만들 것) |
|---|---|---|
| 웹 화면 띄우기 | `WKWebView` (`WebWindow.swift`) | **WebView2** (`Microsoft.Web.WebView2` NuGet, Windows 10/11에 런타임 기본 설치) |
| 메뉴 막대 / 트레이 아이콘 | `NSStatusItem` | `NotifyIcon` + `ContextMenuStrip` |
| 전역 단축키 | Carbon `RegisterEventHotKey` (`HotKey.swift`) | Win32 `RegisterHotKey` + `WM_HOTKEY` |
| 녹음 시작 때 앞 앱 기억 | `NSWorkspace.frontmostApplication` | `GetForegroundWindow()` (자기 창이면 무시) |
| 앞 앱에 넣기 | 클립보드 + ⌘V (`CGEvent`), 클립보드 복원 (`TextInserter.swift`) | 클립보드 + Ctrl+V (`SendInput`), 클립보드 복원 |
| 권한 | 손쉬운 사용 권한 필요 | **필요 없음** |
| 서버 실행·종료 | `Process` (`ServerManager.swift`) | `System.Diagnostics.Process` 로 `.venv\Scripts\python.exe server\server.py` |
| 마이크 허용 | `requestMediaCapturePermissionFor` | `CoreWebView2.PermissionRequested` 에서 `127.0.0.1` + `Microphone`만 허용 |

대안: Tauri(Rust)나 Electron도 가능하지만, 단축키·붙여넣기·트레이를 위해 결국 Win32 API를 써야 하므로
C# 하나로 만드는 것이 가장 단순합니다.

### 4.2 웹 화면과 앱 사이 약속 (Mac과 동일)

`web/app.js`는 Mac과 Windows를 같은 방식으로 다룹니다. 앱은 아래 약속만 지키면 됩니다.

**페이지 → 앱** (`window.chrome.webview.postMessage(obj)` → `CoreWebView2.WebMessageReceived`, `e.WebMessageAsJson`)

| type | 내용 | 앱이 할 일 |
|---|---|---|
| `state` | `{recording, processing, organizing, seconds}` 상태가 바뀔 때마다 | 트레이 아이콘·툴팁 갱신. `recording`이 false→true로 바뀌면 "녹음 시작" 처리(아래) |
| `insertPermission` | 사용자가 "앞 앱에 넣기"를 켰을 때 | Windows는 권한이 필요 없으므로 바로 `insertPermission(true)` 응답 |
| `insert` | `{text, source: "organized" \| "raw"}` 녹음이 끝나고 넣을 글 | 기억해 둔 앞 창에 붙여 넣기 |

**앱 → 페이지** (`webView.CoreWebView2.ExecuteScriptAsync("…")`)

| 호출 | 언제 |
|---|---|
| `window.gqaiNative.toggle()` | 전역 단축키나 트레이 메뉴로 시작/중지할 때 |
| `window.gqaiNative.inserted("메시지")` | 넣기를 끝냈거나 실패했을 때(문자열은 JSON으로 이스케이프) |
| `window.gqaiNative.insertPermission(true)` | `insertPermission` 메시지에 대한 답 |

페이지는 `window.chrome.webview`가 있으면 단축키 안내를 `Ctrl+Alt+R`로 표시합니다.

### 4.3 녹음 시작 → 넣기 흐름

Mac의 `TextInserter.swift`와 같은 규칙입니다.

1. 단축키가 눌리면, 녹음 중이 아닐 때 **지금 앞에 있는 창**(`GetForegroundWindow`)과 시각을 기억합니다.
   자기 창이면 대상 없음으로 둡니다.
2. 페이지에 `toggle()`을 보냅니다.
3. 페이지가 `state.recording = true`를 보내 오면, 5초 안에 기억한 창이 있을 때만 그 창을 "넣을 대상"으로 확정합니다.
   (앱 창의 버튼으로 시작하면 대상이 없고, 결과는 앱 안에만 남습니다.)
4. 녹음이 끝나면 페이지가 `insert`를 보냅니다.
5. 앱은
   1) 현재 클립보드 내용을 저장하고,
   2) 넣을 글을 클립보드에 넣은 뒤,
   3) 대상 창을 앞으로 가져오고(대부분 이미 앞에 있음),
   4) `SendInput`으로 Ctrl+V를 보내고,
   5) 0.5~1초 뒤 클립보드가 그사이 바뀌지 않았으면 원래 내용으로 되돌립니다.
6. 결과를 `inserted("…에 넣었습니다")`로 페이지에 알립니다.

### 4.4 코드 스케치 (C#)

검증하지 않은 뼈대입니다. 오류 처리와 해제는 생략했습니다.

```csharp
// 전역 단축키: Ctrl+Alt+R
[DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr hWnd, int id, uint mod, uint vk);
const uint MOD_ALT = 0x1, MOD_CONTROL = 0x2, MOD_NOREPEAT = 0x4000;
RegisterHotKey(form.Handle, 1, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, (uint)Keys.R);
// Form.WndProc에서 m.Msg == 0x0312 (WM_HOTKEY) 이면 Toggle()

// 앞 창 기억
[DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
IntPtr front = GetForegroundWindow();
if (front == form.Handle) front = IntPtr.Zero;

// WebView2 연결
await webView.EnsureCoreWebView2Async();
webView.CoreWebView2.PermissionRequested += (s, e) => {
    e.State = e.Uri.StartsWith("http://127.0.0.1") && e.PermissionKind == CoreWebView2PermissionKind.Microphone
        ? CoreWebView2PermissionState.Allow : CoreWebView2PermissionState.Deny;
};
webView.CoreWebView2.WebMessageReceived += (s, e) => Handle(JsonDocument.Parse(e.WebMessageAsJson).RootElement);
webView.CoreWebView2.Navigate($"http://127.0.0.1:{port}/");

// 붙여 넣기 (STA 스레드에서)
var saved = Clipboard.GetDataObject();              // 복원용. 형식이 많은 앱은 텍스트만 저장해도 충분
Clipboard.SetText(text);
SetForegroundWindow(target);                         // 4.5의 제한 참고
SendCtrlV();                                         // SendInput: Ctrl down, V down, V up, Ctrl up
await Task.Delay(800);
if (Clipboard.GetText() == text && saved != null) Clipboard.SetDataObject(saved, true);
```

### 4.5 Windows에서 주의할 점

1. **단축키:** Windows에서 Alt+Shift는 입력 언어 전환 키입니다. Mac과 같은 Alt+Shift+R을 쓰면
   한/영 전환과 부딪칠 수 있어 **Ctrl+Alt+R**을 권합니다. 다만 일부 키보드 배열에서 Ctrl+Alt는 AltGr로 동작하니
   설정으로 바꿀 수 있게 하세요.
2. **앞 창으로 전환 제한:** Windows는 백그라운드 앱의 `SetForegroundWindow`를 막는 경우가 있습니다.
   대개 사용자가 대상 앱에 그대로 있으므로 전환이 필요 없지만, 실패하면 클립보드에 남겨 두고 알려 주세요.
   (`AttachThreadInput`이나 `AllowSetForegroundWindow` 같은 우회법이 있으나 동작이 일정하지 않습니다.)
3. **관리자 권한 앱:** 관리자 권한으로 실행된 창에는 일반 앱이 `SendInput`을 보낼 수 없습니다(UIPI).
   이때도 클립보드에 남기고 알려 주세요.
4. **마이크 권한:** 설정 → 개인 정보 및 보안 → 마이크 → "데스크톱 앱에서 마이크에 액세스하도록 허용"이 켜져 있어야 합니다.
5. **한글 입력기:** 붙여 넣기 직전에 대상 창에서 글자를 조합 중이면 결과가 섞일 수 있습니다. 붙여 넣기 전 50~100ms 기다리세요.
6. **서명:** 각자 빌드해서 쓰면 SmartScreen 경고는 대개 문제가 되지 않습니다. 남에게 exe를 나눠 줄 때만 코드 서명이 필요합니다.
7. **클립보드 충돌:** 클립보드 관리 프로그램이 클립보드를 잡고 있으면 `Clipboard.SetText`가 실패할 수 있습니다. 몇 번 재시도하세요.

## 5. 설치 스크립트 (`setup-windows.ps1`)를 만든다면

`scripts/setup-mac.sh`와 같은 순서를 PowerShell로 옮기면 됩니다.

1. Git, Python 3.10+, (빌드 시) CMake·MSVC 확인
2. whisper.cpp 릴리스 zip을 받아 풀거나 CMake로 빌드 (CUDA/Vulkan/CPU 선택)
3. 모델 다운로드 (`Invoke-WebRequest`)
4. `.venv` 만들고 `pip install -r requirements.txt`
5. `config.example.env` → `config.env` 복사, `GQAI_WHISPER_BIN_DIR`·`GQAI_WHISPER_MODEL` 맞추기

## 6. 다 만들었다면 확인할 것

- [ ] 브라우저로 `http://127.0.0.1:7860` 에서 말하면 원문이 쌓이고, 쉬면 정리된 글이 붙는다
- [ ] 앱 창에서 마이크 권한을 묻지 않고(또는 한 번만 묻고) 녹음된다
- [ ] 메모장에 커서를 두고 Ctrl+Alt+R → 말하기 → Ctrl+Alt+R 하면 정리된 글이 메모장에 들어간다
- [ ] 붙여 넣은 뒤 클립보드가 원래 내용으로 돌아온다
- [ ] Chrome 주소창, Slack, Claude 데스크톱 앱 입력창에도 들어간다
- [ ] 관리자 권한 창에서는 클립보드에 남고 안내가 뜬다
- [ ] 창을 닫아도 트레이에서 계속 동작하고, 종료하면 `whisper-server.exe`도 함께 종료된다

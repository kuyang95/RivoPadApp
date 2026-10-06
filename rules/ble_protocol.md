# BLE 프로토콜 (Rivo 리모컨)

점검일 2026-10-06 · 기준 코드 `c0b9f54a`

iPad 앱은 BLE 페리페럴 **Rivo Three / Rivo Mini** 키패드의 버튼 입력을 받아 앱 내부 기능을 조작한다. 구현은 `shortcuts_example/RivoRemote/`. Android 와 같은 펌웨어 프로토콜.

## UUID / CoreBluetooth 설정

`RivoRemote/RivoRemoteManager.swift` · `RivoRemoteManager`

| 식별자 | 값 | 용도 |
|---|---|---|
| 쓰기 특성 (앱 → 기기) | `6E400004-B5A3-F393-E0A9-E50E24DCCA9E` (`uartWriteCharacteristic`) | 시간 동기화 패킷 쓰기. Nordic 표준 RX(`…0002`)가 아닌 `…0004` — 리보 펌웨어 비표준, 변경 금지 |
| notify 특성 (기기 → 앱) | `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` (`uartNotifyCharacteristic`) | 버튼 패킷 notify (`setNotifyValue(true)`) |
| 백그라운드 동작 | Info.plist `UIBackgroundModes` = `bluetooth-central` | 사용자가 연결한 기기의 버튼 수신 유지. 중앙 장치 복원 식별자는 사용하지 않음 |
| 스캔 | `scanForPeripherals(withServices: nil, options: [AllowDuplicates: false])` | 서비스 필터 없이 스캔 후 아래 분류기로 선별 |
| 연결 타임아웃 | 10초 (`scheduleConnectionTimeout`, `Task.sleep 10_000_000_000ns`) | 실패 후 사용자가 다시 선택해야 연결 |
| 쓰기 타입 | 특성이 `.writeWithoutResponse` 지원 시 우선, 아니면 `.withResponse` (`syncTime`) | |

CCC descriptor 를 직접 쓰지 않는다 (CoreBluetooth 가 처리) — Android 문서의 `00002902-…` 항목은 iOS 에 없음.

## 디바이스 식별

`RivoRemote/RivoRemoteProtocol.swift` · `RivoDeviceType.from(serviceUUID:)`, `from(deviceName:)`, `RivoAdvertisementClassifier.match`

| 기기 | 광고 서비스 UUID | 이름 prefix (소문자·영숫자만 남긴 뒤) |
|---|---|---|
| `.three` (Rivo Three) | `f120` 또는 `0000f120…` | `rivo3`, `rivothree` |
| `.mini` (Rivo Mini) | `f121` 또는 `0000f121…` | `rivomini` |

우선순위: 서비스 UUID → 광고 이름 → 페리페럴 이름 (`RivoDiscoverySource`). 저장 기기 정보로 식별하거나 자동 연결하지 않는다.

## 수동 연결 흐름

`RivoRemoteManager.swift` · `RivoRemoteManager`, `RivoDeviceSelectionPolicy`. 화면 진입은 `RivoRemoteView.swift` · `RivoRemoteView`의 `activateAndScan` 호출.

- 앱 전역에서 매니저를 유지한다(`shortcuts_exampleApp.swift` · `shortcuts_exampleApp`). 초기 상태는 `inactive`이며 앱 시작 시 중앙 장치를 만들지 않는다. 리모컨 화면에 진입하거나 검색 버튼을 누르면 중앙 장치를 준비하고 주변 검색을 시작한다.
- 발견한 기기는 사용자가 선택해야 연결한다. 검색 결과는 내부에 여러 기기를 보관하지만 화면에는 `strongestDiscoveredDevice` 한 대만 표시한다. RSSI `127`은 유효하지 않은 신호값으로 취급해 최하위로 둔다.
- 연결 시작 시 검색을 중지하고 10초 타이머를 시작한다. BLE 연결 후 전체 GATT 서비스를 검색하고 각 서비스에서 UART 쓰기·알림 특성을 찾는다. 쓰기 특성, 활성화된 알림 구독, 기기 타입이 모두 있어야 `ready`가 된다.
- 연결 실패·연결 해제·준비 타임아웃 후 자동 재연결하지 않는다. 사용자가 검색 결과의 기기를 다시 선택한다. 주변 검색 자체에는 시간 제한이 없다.
- Bluetooth가 꺼지거나 재설정되면 현재 연결 정보를 정리한다. 다시 켜졌을 때 검색 요청이 남아 있으면 검색만 재개하며, 연결은 사용자의 선택을 기다린다.
- `disconnect`는 검색·연결을 종료하고 `stopScanning`은 검색을 중지한다. `searchForAnotherDevice`는 현재 연결을 종료하고 주변 검색으로 전환한다. 연결 준비 중에는 검색·기기 선택 버튼을 비활성화한다.
- 기기 UUID·타입·Bluetooth 활성화 이력을 저장하지 않는다. 이전 버전의 `rivo.remote.peripheralIdentifier`, `rivo.remote.deviceType`, `rivo.remote.hasActivatedBluetooth` 값은 매니저 초기화 시 제거한다.
- CoreBluetooth 중앙 장치 상태 복원을 사용하지 않는다. 앱 재시작 후에는 다시 수동 연결한다. 종료한 연결의 지연된 콜백은 현재 연결 상태에 반영하지 않는다.
- 연결 준비 후 시간을 자동 전송한다. 전송 성공 후 12시간마다 다시 전송을 예약하며 연결 해제 시 취소한다(`noteTimePacketSent`, `schedulePeriodicTimeSync`). 단계별 연결 진단은 최근 80건을 UserDefaults에 보관한다(`recordDiagnostic`). 과거 진단의 `reconnecting` 값은 디코딩 호환을 위해 유지한다.

## 패킷 조립 / 파싱

`RivoRemoteProtocol.swift` · `RivoPacketAssembler`, `RivoRemotePacketParser`

- 프레임 시작 `0x61 0x74 0x42 0x54` (`"atBT"`), 바이트 4-5 = payload 길이(LE), 헤더+트레일러 10바이트, 최대 65_545바이트. MTU 단편은 `RivoPacketAssembler.append` 가 버퍼링해 완성 패킷만 반환.
- `bytes[6] == 0` → 키 이벤트, `bytes[7]` 이 키 문자. `bytes[6] == 2` → 시퀀스 문자열 (`bytes[7]` 길이, ISO Latin-1). 그 외 무시.
- 시퀀스 `"a/"` = 음성 명령 트리거 (`RivoRemoteControlCenter.receiveDecision` → `.startVoiceAction`).

### 키 문자 → `RivoButton`

| 버튼 | 누름 | 뗌 | 버튼 | 누름 | 뗌 |
|---|---|---|---|---|---|
| L1 | `-` | `_` | 1 | `1` | `!` |
| L2 | `[` | `{` | 2 | `2` | `@` |
| L3 | `;` | `:` | 3 | `3` | `#` |
| L4 | `,` | `<` | 4 | `4` | `$` |
| R1 | `=` | `+` | 5 | `5` | `%` |
| R2 | `]` | `}` | 6 | `6` | `^` |
| R3 | `'` | `"` | 7 | `7` | `&` |
| R4 | `\` | `\|` | 8 | `8` | `*` |
| * (`star`) | `.` | `>` | 9 | `9` | `(` |
| # (`sharp`) | `/` | `?` | 0 | `0` | `)` |

### 제스처

`RivoRemote/RivoButtonGestureInterpreter.swift` · `RivoButtonGestureConfiguration.androidCompatible`: `pressDelay 0.010`, `releaseDelay 0.050`, `longPressDelay 0.500`, `doubleTapInterval 0.300`, `missingReleaseTimeout 3.000` 초. 결과 `RivoButtonAction`: `pressed / released / longPressed / longPressEnded / doubleTapped / doubleTapEnded`.

### 시간 동기화 (앱 → 기기)

`RivoTimeSyncPacketEncoder.packet(for:)` — 21바이트 `"ATDT"` + 길이 11(LE) + `01 00` + 연도(LE) 월 일 시 분 초 밀리초(LE) + 16바이트 합 checksum(LE, int8 합 & 0xFFFF) + `0x0D 0x0A`. 연결 완료 후 `RivoRemoteManager.syncTime()`.

## 입력 처리 흐름

```
notify (6E400003) → RivoPacketAssembler → RivoRemotePacketParser.parse → RivoRemoteInput
  → RivoButtonGestureInterpreter (press/long/double)
  → RivoScreenRemoteControlCenter.receive (활성 화면이 먼저 소비)        RivoScreenRemoteControl.swift
  → RivoRemoteControlCenter.receiveDecision (빠른 메뉴 / 명령 모드 / 전역 키)  RivoRemoteControlCenter.swift
  → RivoRemoteCommand (.navigate / .screen / .home / .back / .stopSpeech / .appBrightness / .appOrientation …)
상태 → RivoWidgetStatusStore.save → 위젯 갱신
```

## 전역 키 / 빠른 메뉴 (Android MENU 모드 대응)

`RivoRemoteControlCenter.receiveDecision`:

| 입력 | 동작 |
|---|---|
| L1 누름 / L1 두 번 | 빠른 메뉴 토글 (`isMenuPresented`) / 메뉴 열기 |
| R1 누름 / 두 번 | 명령 모드 진입 (두 번이면 안내 음성 포함) |
| R3 | `.stopSpeech` |
| L4 / R4 | 미지원 안내 ("Android의 다른 앱 화면 확대 이동은 iPadOS에서 지원되지 않습니다…") |
| 메뉴 열림 상태 1 / 7 | 첫 항목 / 마지막 항목 |
| 4 / 6 | 이전 / 다음 항목 |
| 2 / 8 | 항목 값 증가 / 감소 (`activateAdjustment`) |
| 5 | 선택 실행 (`activateSelection`) |
| 0 | 메뉴 닫고 `.home` |
| * | 상위 페이지로 (`goBackInMenu`) |

페이지 `RivoQuickMenuPage`: `home, tools, appDisplay, widgets, camera, cameraContrast, text, publication`. 목적지 `RivoQuickDestination`: `aiChat, aiChatHistory, reader, translation, magnifier, liveTextReader, imageDescription, scanner, textSource, settings, remoteSettings`. 메뉴 펼침/색상은 `settings.rivoQuickMenuExpanded.v1` / `settings.rivoQuickMenuColorIndex.v1`.

메뉴는 조작 없이 60초가 지나면 닫는다(`autoCloseDelay`). 60초 안에 다시 열면 직전 페이지와 선택을 복원한다(`sessionRestoreWindow`). 도구·위젯 명령은 실행 후 메뉴를 닫고, 카메라·텍스트·독서 조작은 이어서 누를 수 있도록 유지한다(`shouldCloseMenuAfterSelection`). 모드가 바뀌면 `RivoRemoteModeOverlay`가 이름을 1.15초 보여 주고 모드별 키 안내를 그린다.

카메라 빠른 메뉴의 라이트·전후면 이름은 `MagnifierViewController.onCameraStateChanged` → `MagnifierCameraHost` → `RivoRemoteControlCenter.noteMagnifierState`로 실제 상태를 받는다. 토치 활성 상태는 `AVCaptureDevice.isTorchActive`를 관찰해 반영한다. 카메라 화면이 보일 때만 상태를 전달하며, 명령 전송만으로 성공을 가정해 상태를 뒤집지 않는다.

## 명령 모드 (Android COMMAND 모드 대응)

`RivoRemoteControlCenter.commandModeDecision`: 2 → 클립보드 번역, 3 → 실시간 텍스트 읽기, 4 → 카메라 돋보기, 9 → 이미지 설명 카메라. 5/6/7/*/0/# 은 돋보기를 먼저 열도록 안내. 안내문: "명령 모드. 2 클립보드 번역, 3 실시간 텍스트 읽기, 4 카메라 돋보기, 9 이미지 설명. 카메라를 연 뒤 5 전환, 6 토치, 7 촬영, 별표 0 샵 확대를 사용합니다."

## 화면별 모드 (Android DISPLAY / TEXTVIEW / DAISY 대응)

`RivoScreenRemoteControl.swift` · `RivoScreenRemoteMapper.action(for:on:magnifierMode:localDocumentMode:)`. 활성 화면은 각 View 의 `onAppear` 에서 `RivoScreenRemoteControlCenter.activate(_:)`.

| 화면 `RivoRemoteScreen` | 모드 전환 | 키 매핑 (누름) |
|---|---|---|
| `magnifier`, `liveTextReader` | R1 → 카메라 모드, L2 → 표시 모드 (`RivoMagnifierRemoteMode`) | 카메라: 4 닫기, 5 카메라 전환, 6 토치, 7 촬영, R2 초점, * / 0 / # 줌 −/리셋/+ · 표시: 4/5/6 색상 이전/원본/다음, 7/8/9 임계값 −/리셋/+, */0/# 밝기, R2 반전 |
| `documentScanner` | — | 2 이전 페이지, 4 닫기, 5 회전, 7 촬영, 8 다음 페이지, 9 페이지 추가, 0 문서 열기 |
| `publicationReader` (EPUB/DAISY) | — | 4 이전, 5 재생/정지, 6 다음, 2/8 탐색 단위 이전/다음 |
| `localDocumentReader` | L3 → 텍스트 모드, L2 → 표시 모드 (`RivoLocalDocumentRemoteMode`) | 텍스트: 1 처음, 2 이전 줄, 3 이전 페이지, 4/5/6 글자 −/기본/+, 7 끝, 8 다음 줄, 9 다음 페이지, */0/# 줄간격 · 표시: 4/5/6 색상, R2 반전 · R3 읽기 토글 |
| `localAIChat` | — | 4 이전 문장, 5 다시 읽기, 6 다음 문장, R3 답변 읽기 토글, 시퀀스 `a/` 음성 입력 토글 |
| `voiceAction` | — | 시퀀스 `a/` 취소 |

## 위젯 스냅샷

`RivoRemote/RivoWidgetStatusStore.swift` — App Group 키 `rivo.widget.snapshot.v1`, `RivoWidgetConnectionKind` (`notConnected/connecting/connected/unavailable/failed`), 저장 후 `WidgetCenter.shared.reloadTimelines(ofKind: "RivoStatusWidget")`.

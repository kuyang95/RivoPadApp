# VisionCraft Excel AI Groq Worker

엑셀 채팅 요청을 iOS 앱에서 받아 Groq의 `openai/gpt-oss-20b`로 전달하는 Cloudflare Worker입니다. Groq API 키는 앱이나 저장소에 넣지 않고 Worker의 암호화된 secret으로만 보관합니다.

## 배포

Node.js가 설치된 환경에서 다음을 실행합니다.

```sh
npm install
npx wrangler login
npx wrangler secret put GROQ_API_KEY
npm test
npm run typecheck
npm run deploy
```

`GROQ_API_KEY`에는 Groq Console에서 발급한 키를 입력합니다. 배포 결과가 `https://...workers.dev`라면 앱에 넣을 URL은 다음처럼 API 경로까지 포함해야 합니다.

```text
https://...workers.dev/v1/excel-plan
```

Xcode의 `shortcuts_example` 타깃 Build Settings에서 사용자 정의 설정 `EXCEL_AI_GROQ_PROXY_URL`에 위 URL을 지정합니다. 명령행 빌드라면 다음처럼 덮어쓸 수 있습니다.

```sh
xcodebuild -workspace shortcuts_example.xcworkspace \
  -scheme shortcuts_example \
  EXCEL_AI_GROQ_PROXY_URL=https://...workers.dev/v1/excel-plan \
  build
```

## 인증

Worker는 `X-Firebase-AppCheck` 헤더의 JWT를 Firebase 공개 키로 검증합니다. 현재 `wrangler.jsonc`에는 이 앱의 Firebase project number와 iOS app ID가 설정되어 있습니다. Firebase Console에서 `net.rivo.visioncraft` 앱의 App Check/App Attest 등록을 유지해야 합니다.

Groq 키를 `.dev.vars`, 소스 코드, Info.plist에 커밋하지 마세요. 로컬 시험용 형식은 `.dev.vars.example`에만 있습니다.

## 데이터 처리 범위

AI 명령을 처리할 때 현재 시트 이름, 감지된 표 범위, 병합 범위, 최대 1,500개의 비어 있지 않은 셀 값과 최근 채팅이 Groq로 전송됩니다. Worker는 요청 본문이나 셀 내용을 로그로 남기지 않으며 응답에는 `Cache-Control: no-store`를 설정합니다.

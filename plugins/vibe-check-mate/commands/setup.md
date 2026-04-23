---
description: vibe-check-mate 하네스를 현재 프로젝트에 한 방으로 구성한다 (biome 설정 + husky pre-commit + dev runtime 캡처 + check 스크립트).
---

# vibe-check-mate · setup

아래 절차를 순서대로 수행하고 첫 실패 시점에 중단 후 보고한다.

## 1. 에셋 복사 — plugin → 프로젝트 루트
`${CLAUDE_PLUGIN_ROOT}`에서 현재 프로젝트 루트(`.`)로 복사:
- `scripts/run-static-check-with-logs.sh` → `./scripts/run-static-check-with-logs.sh`
- `scripts/dev-runtime.sh` → `./scripts/dev-runtime.sh`
- `scripts/client-error-receiver.py` → `./scripts/client-error-receiver.py` (브라우저 에러 수신용)
- `scripts/client-error-reporter.js` → `./scripts/client-error-reporter.js` (브라우저에서 로드될 reporter)
- `biome-config/biome.base.json` → `./biome-config/biome.base.json`
- `biome-config/biome.react.json` → `./biome-config/biome.react.json`
- `biome-config/biome.strict.json` → `./biome-config/biome.strict.json`

reporter 를 **웹 루트로 서빙 가능한 위치**에 복사 (프로젝트 상태별 분기):
- `public/` 가 이미 존재 → `public/client-error-reporter.js` 에 복사
- `public/` 는 없지만 `vite.config.*` 존재 → `public/` 생성 + 복사
- 위 둘 다 아니지만 `app/layout.tsx` / `app/root.tsx` / `pages/_document.tsx` 중 하나 존재 (Next / Remix) → `public/` 생성 + 복사 (framework 관례)
- 위 전부 해당 없고 루트에 `index.html` 만 있는 경우 (plain SPA / static) → `index.html` 과 **같은 디렉터리** (보통 프로젝트 루트) 에 `client-error-reporter.js` 복사해서 정적 서버가 `/client-error-reporter.js` 로 서빙 가능하게 만듦

복사 후 실행 권한:
```bash
chmod +x scripts/run-static-check-with-logs.sh scripts/dev-runtime.sh
```
기존 동일 경로 파일이 이미 존재하면 덮어쓰기 여부를 사용자에게 먼저 물어본다.

## 2. `setup-biome-config` 스킬 호출
- React/strict 여부를 package.json·tsconfig.json·소스 구조로 판정
- `@biomejs/biome`가 없으면 `pnpm add -D @biomejs/biome`
- 루트 `biome.json`의 `extends`를 감지된 preset으로 구성 (기존 커스텀 규칙은 보존)

## 3. `create-pre-commit-hook` 스킬 호출
- `pnpm add -D husky` + `pnpm dlx husky init`
- package.json scripts에 병합: `lint`, `lint:fix`, `typecheck`, `check: "bash ./scripts/run-static-check-with-logs.sh"`
- `.husky/pre-commit` 교체:
  ```sh
  #!/bin/sh
  pnpm run check || exit 1
  ```
- `chmod +x .husky/pre-commit`

## 4. Dev runtime 캡처 연결 (`runtime-auto-fix` 스킬 세팅 룰 참조)
- 기존 `scripts.dev`가 있으면 `scripts.dev:raw`로 이동 (단 `dev:raw`가 이미 있으면 덮어쓰지 않음).
- `scripts.dev` ← `"bash ./scripts/dev-runtime.sh"`.

## 4-B. 브라우저 에러 reporter 자동 주입 (framework 감지)

### Step 1. Framework 감지 (우선순위)
1. `app/layout.tsx` 또는 `app/layout.jsx` 존재 → `target = next-app`, file = 해당 layout
2. `pages/_document.tsx` 또는 `pages/_document.jsx` 존재 → `target = next-pages`, file = 해당 _document
3. `app/root.tsx` 존재 AND `package.json` deps 에 `@remix-run/*` → `target = remix`, file = `app/root.tsx`
4. 루트에 `index.html` 존재 → `target = vite-or-spa`, file = `index.html`
5. 위 모두 해당 안 됨 → 자동 주입 skip, 아래 Step 5 fallback 으로 이동

### Step 2. 주입 전 안전 검사 (Read 만, 파일 수정 전)
대상 파일을 Read 한 뒤 아래 조건을 **모두** 만족해야 주입 진행:

**Idempotency 체크 (거짓 양성 방지)**: 실제 `<script>` 태그에만 매칭.
- 조건: 파일에 다음 중 하나가 존재하면 이미 주입된 것으로 판단하고 skip:
  - `<script src="/client-error-reporter.js"` (HTML/JSX 구분 없이 literal tag 문자열로 시작)
  - `<Script src="/client-error-reporter.js"` (Next.js `next/script` 컴포넌트)
- **제외**: `<code>`, `<pre>`, 주석, 또는 escape된 `&lt;script`, 문자열 리터럴 안에 설명용으로 나타나는 경우는 무시. 탐지 시 "실제 태그가 아닌 리터럴/주석 텍스트"로 판정 → skip 하지 않고 계속 진행.
- 판정 절차: 파일을 Read 해서 실제 렌더되는 element opening (`<script` 또는 `<Script`) 로 시작하고 reporter URL 이 attribute 에 포함된 경우만 "이미 주입" 으로 간주. 단순 substring 매칭 금지.

**삽입 위치 검증**: 대상 opening 태그가 **정확히 1회** 나타나야 함:
- `next-app` / `remix` / `vite-or-spa` → `<body>` (소스에 `<body>` 가 없고 `<head>` 만 있으면 `<head>`)
- `next-pages` → `<Head>`
- 0개 → 주입 불가
- 2개 이상 → 모호, 주입 불가

조건 실패 시 **Edit 호출하지 않고** Step 5 fallback 으로.

### Step 3. 주입 실행 (Edit tool)
- `old_string` = 대상 태그의 정확한 opening 라인 (원본에서 그대로 복사)
- `new_string` = 같은 opening 라인 + 줄바꿈 + 2칸 들여쓰기된 `<script>` 태그
- 삽입할 태그:
  - TSX (`next-app`, `next-pages`, `remix`) → `<script src="/client-error-reporter.js" async />`
  - HTML (`vite-or-spa`) → `<script src="/client-error-reporter.js"></script>`

### Step 4. 주입 후 검증 및 롤백
Edit 직후 같은 파일을 다시 Read:
- 주입한 literal 태그 (`<script src="/client-error-reporter.js"` 또는 `<Script src="/client-error-reporter.js"`) 가 실제 opening position 에 존재 → 성공, 리포트에 "auto-injected to `<path>`:<line>" 기록
- 태그 없음 or 파일 구조가 깨져 보임 → **롤백 시도**:
  1. 역 Edit (new_string → old_string) 로 원상 복구 시도
  2. 역 Edit 도 실패 → 사용자에게 `git diff <file>` 확인 및 `git restore <file>` 안내
  3. Step 5 fallback 으로

### Step 5. Fallback — 수동 삽입 스니펫 제공
자동 주입이 skip 또는 실패한 경우, 리포트 하단에 **반드시** 다음을 명시:

```
⚠️ 자동 주입 실패/skip — 이유: <구체적 원인 (태그 모호 / 파일 없음 / 롤백됨 / 이미 주입됨)>

아래 스니펫을 직접 복사해서 해당 위치에 넣어주세요.

[Next.js app router]  app/layout.tsx 의 <body> 바로 안:
  <script src="/client-error-reporter.js" async />

[Next.js pages router] pages/_document.tsx 의 <Head> 안:
  <script src="/client-error-reporter.js" async />

[Remix]               app/root.tsx 의 <head> 안:
  <script src="/client-error-reporter.js" async />

[Vite / 순수 SPA]      index.html 의 <head> 안:
  <script src="/client-error-reporter.js"></script>
```

> reporter 는 `localhost` / `127.0.0.1` 접속 시에만 동작. 프로덕션 번들에서는 no-op.

## 5. 검증
- `pnpm run check`를 실행해 lint/typecheck 통과 시 `.check-static/`이 생성되지 않는지 확인.
- 실패 케이스를 일부러 유도해 `.check-static/{lint.log, typecheck.log, error-files.txt}` 3개가 생성되는지 확인.
- `.gitignore`에 `.check-static/`, `.check-runtime/` 추가 권장.

## 6. 보고 포맷
아래 항목을 요약:
- 새로 생성된 파일 목록 (`path`)
- 선택된 biome preset
- 설치된 husky 버전
- 기존 파일 유지 여부와 이유
- 다음 사용 가이드:
  - 커밋이 lint/typecheck로 차단되면 → `static-auto-fix` 스킬 호출
  - dev 서버(서버사이드 에러) 또는 브라우저(클라이언트 에러)에서 런타임 에러 발생하면 → `runtime-auto-fix` 스킬 호출
- 브라우저 에러 reporter 주입 여부와 권장 스니펫을 별도 섹션으로 명시

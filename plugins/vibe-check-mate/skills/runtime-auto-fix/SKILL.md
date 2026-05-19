---
name: runtime-auto-fix
description: Use automatically when .check-runtime/AGENT_ACTION_REQUIRED.md exists. Analyze the locked first runtime error snapshot, apply the minimal code fix, then restart dev to verify the same signature does not reappear.
---

# 목적

개발 서버 실행 중 캡처된 런타임 에러 evidence를 기준으로 원인을 분석하고, 관련 파일만 최소 수정한다.

`dev-runtime.sh`는 기본적으로 dev server를 종료하지 않는다. 대신 첫 런타임 에러가 감지되는 순간 `.check-runtime/first-error.log`와 관련 source snapshot을 잠그고, `AGENT_ACTION_REQUIRED.md`를 생성한다.

# 입력

- `.check-runtime/AGENT_ACTION_REQUIRED.md`
- `.check-runtime/first-error.log`
- `.check-runtime/error-signature.txt`
- `.check-runtime/source-context.md`
- `.check-runtime/error-files.txt`
- `.check-runtime/runtime-fix-files.txt`
- `.check-runtime/static-gate-error-files.txt` (static gate 실패 시)
- `.check-runtime/runtime.log`
- `.check-runtime/meta.txt`
- `package.json`

# 전제

- `.check-runtime/first-error.log`는 현재 dev 세션의 첫 런타임 에러 snapshot이다.
- `runtime.log`는 계속 append되는 live log이며 1차 근거가 아니다.
- 브라우저 fetch/XMLHttpRequest 실패와 4xx/5xx/slow request는 `[CLIENT_NETWORK]` evidence로 `runtime.log`에 기록될 수 있다.
- 브라우저 receiver는 기본 `9876`부터 사용 가능한 포트를 자동 탐색하고, reporter가 읽을 `client-error-endpoint.json`을 웹 루트에 기록한다.
- dev server는 실행 중일 수 있다.
- `AGENT_ACTION_REQUIRED.md`가 존재하면 이 스킬을 다른 작업보다 먼저 실행한다.

# package.json 설정 보정

1. `package.json`을 읽는다.
2. `scripts.dev`가 `bash ./scripts/dev-runtime.sh`인지 확인한다.
3. wrapper가 아니라면:
   - 기존 `dev` 값을 `dev:raw`로 이동한다.
   - `dev`를 `bash ./scripts/dev-runtime.sh`로 교체한다.
4. `dev:raw`가 이미 존재하면 덮어쓰지 않는다.

# 스크립트 존재 확인 및 권한 설정

1. `scripts/dev-runtime.sh` 존재 여부를 확인한다.
2. 없으면 생성한다.
3. 항상 실행 권한을 보장한다:

```bash
chmod +x scripts/dev-runtime.sh
```

# 실행 및 최신화

1. `pnpm run dev`를 실행하면 `.check-runtime/`이 생성된다.
2. 서버/브라우저 에러가 감지되면 다음 파일이 생성된다:
   - `first-error.log`
   - `error-signature.txt`
   - `error-files.txt`
   - `source-context.md`
   - `AGENT_ACTION_REQUIRED.md`
3. 기본값은 live mode다. dev server를 계속 유지한다.
4. 에러 감지 시 dev server 종료가 필요하면 `VIBE_DEV_AUTOKILL=1`을 명시적으로 사용한다.

# 분석 규칙

1. 반드시 `.check-runtime/AGENT_ACTION_REQUIRED.md`를 먼저 읽는다.
2. 반드시 `.check-runtime/first-error.log`를 읽는다.
3. 반드시 `.check-runtime/error-signature.txt`를 읽는다.
4. 반드시 `.check-runtime/source-context.md`를 읽는다.
5. `.check-runtime/runtime.log`는 보조 자료로만 사용한다.
6. later live logs보다 first failure snapshot을 우선한다.
7. `.check-runtime/first-error.log`를 덮어쓰지 않는다.
8. `[CLIENT_NETWORK]`가 원인 후보이면 인접한 `[CLIENT_NETWORK_HEADERS]`, `[CLIENT_NETWORK_BODY]`, `[CLIENT_NETWORK_MESSAGE]`를 함께 읽는다.
9. request URL, query string, status, method, headers, body를 원인 분석 근거로 사용한다.
10. `.check-runtime/runtime-fix-files.txt`는 clean restart 중에도 보존되는 runtime-fix 커밋 후보 파일 목록이다.

# 수정 규칙

- `.check-runtime/error-files.txt`에 등장한 파일만 우선 수정 대상으로 삼는다.
- 로그와 source context에 직접 근거가 있는 코드 버그만 수정한다.
- 최소 수정만 수행한다.
- refactor 금지
- 새로운 파일 생성 금지
- 전체 프로젝트 탐색 금지
- 환경/설정/외부 API 문제를 코드 수정으로 억지 해결하지 않는다.
- request body, headers, query string은 근거로 사용할 수 있지만, token/password/authorization/cookie류 redacted 값은 복원하려 하지 않는다.

# 검증 규칙

수정 후에는 clean dev restart와 static gate를 모두 통과해야 한다. HMR만으로 성공 판단하지 않는다.

1. 기존 first snapshot의 핵심 정보를 먼저 기록한다:
   - `error-signature.txt`의 첫 줄
   - 수정 대상 파일 목록
   - 원인 요약
2. `.check-runtime/meta.txt`의 `dev_pid`가 살아 있으면 종료한다.
3. `pnpm run dev`를 재실행한다.
4. 최대 30초 동안 다음 중 하나를 기다린다:
   - dev server ready signal
   - 같은 error signature 재발
   - 다른 runtime error action file 생성
   - timeout
5. 같은 signature가 재발하지 않고 server ready 상태면 runtime gate 통과로 판단한다.
6. 검증용 dev server를 종료한다.
7. 반드시 `pnpm run check`를 단독 실행한다.
8. `pnpm run check` 통과 → full verification 통과로 판단한다.
9. `pnpm run check` 실패 → `.check-static/error-files.txt`를 `.check-runtime/static-gate-error-files.txt`로 기록한 뒤 `.check-static/AGENT_ACTION_REQUIRED.md`를 읽고 `static-auto-fix`를 runtime-handoff mode로 즉시 실행한다. 이때 runtime 성공 리포트와 commit plan을 출력하지 않는다.
10. `static-auto-fix`가 통과하면 static 수정 파일을 runtime-fix bucket 후보에 포함하고, 다시 1번부터 clean dev restart를 실행해 runtime을 재검증한다.
11. `static-auto-fix`가 실패하거나 사용자 `Y / N` 대기 상태가 되면 static-auto-fix의 정형 리포트를 그대로 출력하고 멈춘다. `.check-runtime/AGENT_ACTION_REQUIRED.md`는 유지한다.
12. 같은 signature가 재발하면 **케이스 4**로 보고하고 `계속 수정할까요? (Y / N)`를 묻는다.
13. 다른 signature가 발생하면 **케이스 5**로 보고하고 `계속 수정할까요? (Y / N)`를 묻는다.
14. 사용자가 `Y`를 선택하면 검증용 dev server를 종료하고, `pnpm run dev`로 최신 `.check-runtime/first-error.log`를 다시 생성한 뒤 다음 attempt를 시작한다.
15. 사용자가 `N`을 선택하면 `.check-runtime/AGENT_ACTION_REQUIRED.md`를 유지하고 종료한다.
16. full verification 통과 시 `.check-runtime/AGENT_ACTION_REQUIRED.md`를 제거한다.

ready signal 예시:
- `Local:`
- `ready`
- `started server`
- `compiled successfully`
- `✓ Ready`

runtime fix 후 static gate는 선택이 아니다. 반드시 `pnpm run check`를 단독 실행한다.

# 종료 조건

- **코드 버그 수정 성공 + clean dev restart 통과 + pnpm run check 통과** → `AGENT_ACTION_REQUIRED.md` 제거 → 케이스 1 리포트 → 커밋 제안 단계
- **clean dev restart 통과 + pnpm run check 실패** → `static-auto-fix` 즉시 실행 → static 통과 후 runtime clean restart 재검증
- **환경/설정/외부 서비스 문제** → 수정 X → 케이스 2 리포트
- **원인 불명확** → 수정 X → 케이스 3 리포트
- **동일 에러 시그니처 반복** → 케이스 4 리포트 → `계속 수정할까요? (Y / N)`
- **다른 에러 시그니처 발생** → 케이스 5 리포트 → `계속 수정할까요? (Y / N)`
- 사용자가 `Y`를 선택한 경우에만 다음 attempt를 진행한다.

# 에이전트 실행 규칙

- 최신 first snapshot을 source of truth로 사용한다.
- 로그에 직접 근거가 있는 수정만 수행한다.
- 불필요한 개선, 정리, 구조 변경 작업 금지
- 반복 수정 루프 금지
- 지속적으로 비슷한 오류가 발생하면, 반드시 다음 수정 전에 다른 방법과 접근법을 먼저 생각하고 전략을 바꾼다.

# retry 정책

- 실패 시 자동으로 계속 수정하지 않는다.
- 실패 시 반드시 사용자에게 `계속 수정할까요? (Y / N)`를 묻는다.
- `Y`면 최신 source of truth를 다시 생성한다:
  - 기존 dev server 종료
  - 검증용 dev server 종료
  - `pnpm run dev` 재시작
  - 새 `.check-runtime/first-error.log`
  - 새 `.check-runtime/error-signature.txt`
  - 새 `.check-runtime/source-context.md`
- runtime gate 통과 후 static gate에서 실패하면 `static-auto-fix`를 먼저 완료하고, 이후 runtime clean restart를 다시 수행한다.
- 같은 signature가 반복되면 같은 수정 전략을 반복하지 않는다.
- 같은 signature가 2회 이상 반복되면 다음 attempt 전에 원인 가설과 다른 접근법을 먼저 짧게 정리한다.
- `N`이면 action file을 유지하고 리포트한다.

# 커밋 제안

runtime은 static 이후 단계로 간주한다. 따라서 기본 제안은 **runtime-fix 전용 커밋**이다.

단, runtime fix 시작 시점에 다른 staged/working 변경사항이 있으면 이를 버리거나 runtime-fix에 섞지 않는다. 별도 bucket으로 보존해 분할 커밋 계획에 포함한다.

원인이 코드 버그로 분류되고 clean dev restart와 `pnpm run check`가 모두 통과한 경우에만 커밋 + push를 제안한다. 사용자 `Y` 승인 전에는 commit/push하지 않는다.

## Pre-flight 검사

1. `git config user.name`, `git config user.email` 둘 다 비어있지 않아야 한다.
2. `.git/MERGE_HEAD`, `.git/REBASE_HEAD`, `.git/CHERRY_PICK_HEAD`, `.git/REVERT_HEAD` 중 하나라도 존재하면 제안 중단.
3. staged/working 변경이 있으면 runtime-fix 커밋과 섞지 않고 별도 bucket으로 분리한다.

## 제안 절차

1. 커밋 대상 파일을 3조건 모두 만족하는 파일로 좁힌다:
   - `.check-runtime/runtime-fix-files.txt`, `.check-runtime/error-files.txt`, `.check-runtime/static-gate-error-files.txt` 중 하나에 포함
   - `git diff --name-only HEAD` 결과에 포함
   - tracked file
2. 좁혀진 파일 목록, 에러 시그니처, 원인 요약을 보여준다.
3. 메시지 예:
   - existing bucket → 변경 성격에 따라 `docs:` / `test:` / `chore:` / `refactor:` / `fix:`
   - runtime-fix bucket → `fix: resolve runtime verification error`
4. 제안 형식:
   ```text
   ## 🧪 runtime verification commit plan

   [1/N existing]    <메시지>  # 다른 변경사항이 있으면
   [N/N runtime-fix] <메시지>

   검증: `pnpm run dev` 재시작 후 같은 signature 재발 없음 + `pnpm run check` 통과
   승인 시 commit 후 git push 실행. (Y / 수정 / N)
   ```
5. 응답 처리:
   - **Y**: bucket별 파일/patch만 stage → 순서대로 commit → `git push`
   - **수정**: 메시지를 반영해 다시 제안
   - **N**: commit/push하지 않고 working tree 유지

# 리포트 (필수)

아래 템플릿 중 정확히 하나를 복사해서 출력한다. 제목, 항목명, 순서, 빈 줄, 선택지 표기를 바꾸지 않는다. 해당 없는 값은 `없음`으로 채운다. 로그 전문을 붙이지 않는다.

## 케이스 1. 코드 버그로 분류 → 수정 적용

```md
## ✅ runtime fix verified

- **원인 분류**: 코드 버그
- **attempts**: <number>
- **에러 시그니처**: <error-signature summary>
- **수정 내용**: <path — summary; ...>
- **근거**: first-error.log / source-context.md / runtime.log network evidence
- **검증**: 기존 dev server 종료 → pnpm run dev 재시작 → 같은 signature 재발 없음 → pnpm run check 통과
- **정리**: .check-runtime/AGENT_ACTION_REQUIRED.md 제거됨
- **commit plan**:
  - [1/N existing] <message or 없음>
  - [N/N runtime-fix] <message>
- **push**: 승인 시 분할 커밋 후 git push
- **승인**: Y / 수정 / N
```

## 케이스 2. 환경·설정·외부 서비스 문제

```md
## ⚠️ runtime fix skipped

- **원인 분류**: <환경 | 설정 | 외부 API/서비스>
- **증거**: <first snapshot/network evidence summary>
- **상태**: .check-runtime/AGENT_ACTION_REQUIRED.md 유지
- **다음 액션**: <specific next action>
```

## 케이스 3. 원인 불명확

```md
## ⏸ runtime analysis unclear

- **로그 요약**: <first snapshot signature + context>
- **추정 후보**: <candidate 1; candidate 2; candidate 3 or 없음>
- **상태**: .check-runtime/AGENT_ACTION_REQUIRED.md 유지
- **다음 액션**: <required user confirmation>
```

## 케이스 4. 수정 후 동일 signature 재발

```md
## ❌ runtime fix not verified

- **attempts**: <number>
- **수정한 파일**: <files or 없음>
- **재발한 시그니처**: <same signature summary>
- **검증**: pnpm run dev 재시작 후 같은 에러 재발
- **상태**: .check-runtime/AGENT_ACTION_REQUIRED.md 유지
- **다음 액션**: 계속 수정할까요? (Y / N)
```

## 케이스 5. 다른 runtime error 발생

```md
## ⏭ new runtime failure detected

- **기존 시그니처**: <previous signature>
- **새 시그니처**: <new signature>
- **판단**: 기존 오류 수정 여부를 단정하지 않음
- **상태**: 새 .check-runtime/AGENT_ACTION_REQUIRED.md 기준으로 다음 분석 필요
- **다음 액션**: 계속 수정할까요? (Y / N)
```

## 리포트 금지
- 템플릿 밖 설명 추가 금지
- 항목명 변경 금지
- 선택지를 `Y / 수정 / N` 또는 `Y / N` 외 형태로 변경 금지
- 로그 전문 출력 금지
- clean dev restart와 `pnpm run check` full verification 없이 케이스 1 출력 금지

# 금지 사항

- `.check-runtime/AGENT_ACTION_REQUIRED.md`가 있는데 무시하고 다른 작업 진행 금지
- `.check-runtime/first-error.log` 덮어쓰기 금지
- 수정 후 clean dev restart와 `pnpm run check` 검증 없이 성공 보고 금지
- 과거 로그 기반 수정 금지
- 환경 문제를 코드 수정으로 억지 해결 금지
- 반복 수정 루프 금지
- 비슷한 오류가 반복되는데 같은 수정 전략을 재시도하는 것 금지
- 사용자 확인 없이 `git commit` 실행 금지
- 사용자 `Y` 승인 없이 `git push` 실행 금지

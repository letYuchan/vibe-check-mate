---
name: runtime-auto-fix
description: dev 서버를 로그 캡처 모드로 실행하고, 최신 .check-runtime 상태를 기준으로 런타임 에러를 분석 및 최소 수정한다.
---

# 목적
개발 서버 실행 중 발생한 런타임 에러를 `.check-runtime/`에 최신 상태로 기록하고,
이 폴더를 기준으로 원인 분석 및 최소 수정을 수행한다.

# 입력
- .check-runtime/runtime.log
- .check-runtime/meta.txt
- .check-runtime/error-files.txt
- package.json

# 전제
- `.check-runtime/`는 항상 최신 dev 세션의 로그만 의미한다.
- `pnpm run dev`는 `scripts/dev-runtime.sh`를 통해 실행된다.
- 과거 로그는 사용하지 않는다.

# package.json 설정 보정
1. package.json을 읽는다.
2. `scripts.dev`가 `bash ./scripts/dev-runtime.sh`인지 확인한다.
3. wrapper가 아니라면:
   - 기존 `dev` 값을 `dev:raw`로 이동한다.
   - `dev`를 `bash ./scripts/dev-runtime.sh`로 교체한다.
4. `dev:raw`가 이미 존재하면 덮어쓰지 않는다.

# 스크립트 존재 확인 및 권한 설정
1. `scripts/dev-runtime.sh` 존재 여부를 확인한다.
2. 없으면 생성한다.
3. 항상 실행 권한을 보장한다:

chmod +x scripts/dev-runtime.sh

# 실행 및 최신화
1. 현재 dev 서버가 이미 실행 중인지 확인한다.
2. 실행 중이면 종료한다.
3. `pnpm run dev`를 실행한다.
4. `.check-runtime/` 폴더가 최신 상태로 생성되는지 확인한다.

## Dev server 종료 처리
`dev-runtime.sh`(v0.3.0+)는 **runtime 에러 패턴을 감지하면 자동으로 SIGINT**를 날려 dev server를 종료하고 `.check-runtime/`을 finalize한다.
- 감지 패턴: `TypeError:`, `ReferenceError:`, `SyntaxError:`, `Uncaught`, `UnhandledPromise`, `Cannot find module`, `✘ [ERROR]`, `^Error:`
- 에러 발견 후 `VIBE_DEV_AUTOKILL_GRACE`초 (기본 2초) 대기 → 스택트레이스 수집 → SIGINT 전송
- `VIBE_DEV_NO_AUTOKILL=1`로 비활성화 가능 (그 경우 사용자가 직접 Ctrl+C)

스킬 동작:
1. `.check-runtime/meta.txt`의 `ended_at`이 존재하면 auto-kill 또는 수동 종료로 이미 finalize된 상태 → 분석 진입
2. `ended_at`이 없으면 아직 dev server 실행 중 → **케이스 4 리포트** 후 대기 (auto-kill 비활성화했거나 감지 패턴 miss 시 fallback)
3. 브라우저 전용 에러(터미널 로그에 안 남는 Client-only 런타임 에러)는 auto-kill이 감지 못 함 → 사용자 수동 Ctrl+C 필요

# 폴더 분석 규칙
1. `.check-runtime/runtime.log`를 읽는다.
2. `.check-runtime/error-files.txt`를 우선 참조한다.
3. 이 폴더 안의 파일을 최신 런타임 실패 상태의 단일 source of truth로 사용한다.
4. 폴더 밖의 과거 로그나 추측성 컨텍스트는 사용하지 않는다.

# 분석
1. 에러 유형을 다음 중 하나로 분류한다:
   - 코드 버그
   - 환경/설정 문제
   - 외부 API/서비스 문제
2. 코드 버그로 명확한 경우에만 수정한다.

# 수정 규칙
- `.check-runtime/`를 단일 source of truth로 사용한다.
- `.check-runtime/error-files.txt`에 등장한 파일만 우선 수정 대상으로 삼는다.
- 최소 수정만 수행한다.
- refactor 금지
- 새로운 파일 생성 금지
- 전체 프로젝트 탐색 금지
- 로그에 직접 근거가 있는 수정만 허용한다

# 종료 조건 (각 지점은 반드시 리포트 케이스와 매핑)
- **코드 버그 수정 성공** → **케이스 1 리포트** → "커밋 제안" 단계 진입.
  - 커밋 제안 중 Pre-flight 실패 → 케이스 1은 이미 출력된 상태에서 **케이스 5 리포트도 추가 출력**.
- **환경/설정/외부 서비스 문제로 분류** → 수정 X → **케이스 2 리포트** 후 종료.
- **원인 불명확** → 수정 X → **케이스 3 리포트** 후 종료.
- **dev server가 아직 실행 중** (`meta.txt`의 `ended_at` 없음, 로그 finalize 전) → 수정 X → **케이스 4 리포트** 후 대기 (사용자가 Ctrl+C 후 재호출 필요).
- **동일 에러 시그니처가 반복**되면 즉시 종료 → **케이스 3 변형** 리포트 (이유: "동일 에러 반복, 추가 수정 중단").
- 최대 수정 시도 1회, 수정 후 dev 재실행 1회로 제한.

# 커밋 제안 (코드 수정 적용 후)
원인이 "코드 버그"로 분류돼 실제 수정이 반영된 경우에만 커밋을 제안한다. 자동 커밋은 하지 않는다.

## Pre-flight 검사
1. **git 정체성 확인**: `git config user.name`, `git config user.email` 둘 다 비어있지 않아야 한다. 비면 안내 후 제안 중단.
2. **git 진행 상태 확인**: `.git/MERGE_HEAD`, `.git/REBASE_HEAD`, `.git/CHERRY_PICK_HEAD`, `.git/REVERT_HEAD` 중 하나라도 존재하면 제안 중단.
3. **스테이징 감지 → 분기**: `git diff --cached --name-only`가 비어있지 않으면 block하지 말고 아래 **"스테이징 충돌 시 자동 분할 + push"** 경로로 분기.

## 제안 절차 (pre-flight 통과 시에만)
1. 커밋 대상 파일을 3조건 **모두** 만족하는 파일로 좁힌다:
   - (a) `.check-runtime/error-files.txt`에 포함
   - (b) `git diff --name-only HEAD` 결과에 포함 (실제 수정됨)
   - (c) untracked 아님
2. 좁혀진 파일 목록, 에러 시그니처, 원인 요약을 보여준다.
3. Conventional Commits 메시지를 생성한다:
   - `fix: <한 줄로 런타임 에러 설명>` (예: `fix: guard null config before accessing port`)
4. "이 메시지로 커밋할까요? (Y / 메시지 수정 / n)" 형식으로 확인한다.
5. 응답 처리:
   - **Y**: `git add <좁혀진 파일 목록>` → `git commit -m "<제안 메시지>"`
   - **메시지 수정**: 사용자가 준 메시지로 커밋
   - **n**: 커밋하지 않고 working tree를 유지한 채 종료

## 스테이징 충돌 시 자동 분할 + push (Pre-flight 3번 진입)
기존 스테이지된 변경이 존재하면 중단하지 않고 아래 절차로 **커밋 2개 분할 + push 자동 실행**.

1. **pre-stage 메시지 생성**: `git diff --cached`로 변경 성격 분석 → Conventional Commits prefix 추론 → 1줄 메시지 작성.

2. **fix 메시지 생성**: 기존 제안 절차 그대로 (`fix: <런타임 에러 설명>`).

3. **단일 통합 제안**:
   ```
   ## 🗂 커밋 분할 + push 제안
   
   [1/2 pre-staged] <메시지1>
   [2/2 fix]        <메시지2>
   
   승인 시 위 순서로 커밋 후 git push 실행. (Y / 수정1 / 수정2 / n)
   ```

4. **응답 처리**:
   - **Y** → `git commit -m "<1>"` (pre-stage는 이미 staged) → `git add <fix 좁혀진 목록>` → `git commit -m "<2>"` → `git push`
   - **수정1** / **수정2** → 해당 메시지만 교체해 재확인 → Y
   - **n** → 아무것도 실행하지 않고 종료

5. **push 실패 시**: 케이스 2 리포트로 전환해 이유 전달, 커밋 2개는 로컬에 남김.

## 커밋 규칙
- Co-Authored-By 추가 금지 (Claude 포함 어떤 공저자도 넣지 않는다)
- prefix는 주로 `fix:` (런타임 에러 수정), 부수적 리팩터가 섞이면 `refactor:` 허용
- 간결·명확한 메시지
- `git push`는 **기본 자동 실행하지 않는다**. 예외: 분할 경로에서 사용자가 Y 게이트로 명시 승인한 경우만 자동 push.
- `git add -A`나 `git add .` 금지 — 좁혀진 파일 목록만 명시적으로 스테이징.

## 커밋 제안 생략 조건
- 원인이 환경·설정·외부 서비스 문제면 수정 자체를 안 하므로 제안도 안 한다
- 분석이 불명확해서 수정을 안 한 경우 제안 안 한다
- 동일 에러 시그니처가 반복되는 경우 제안 안 한다
- pre-flight 1·2번(git 정체성, 진행 상태) 중 하나라도 실패하면 제안하지 않는다 (스테이징 충돌은 더 이상 block 사유 아님)
- 좁혀진 파일 목록이 비어있으면 제안하지 않는다
- `error-files.txt` 밖 파일이 수정됐다면 이유 보고 후 종료

# 에이전트 실행 규칙
- 최신 `.check-runtime/`만 사용한다.
- 추가적인 프로젝트 전체 검사 명령을 임의로 실행하지 않는다.
- 로그 기반으로만 판단한다.
- 불필요한 개선 작업 금지
- 반복 수정 루프 금지
- **bash 명령을 `;`로 여러 개 chain 금지** — 마지막 명령의 exit code만 반환되므로 검증 실패/성공을 오판하게 됨. 필요하면 조건부 실행(`if cmd; then ... fi`) 또는 개별 tool call로 분리.

# 리포트 (필수)
**모든 종료 지점에서 반드시 케이스 1~5 중 정확히 하나의 리포트를 출력한다. 침묵 exit 절대 금지.**
코드 버그 수정 성공 후 커밋 제안 단계에서 Pre-flight가 실패하면 **케이스 1 + 케이스 5 리포트 2개**를 모두 출력한다.

케이스별 정해진 구조로 보고한다. 장황함 금지.

## 케이스 1. 코드 버그로 분류 → 수정 적용
제목: `## ✅ 런타임 에러 수정 적용`
본문 항목:
- **원인 분류**: 코드 버그
- **에러 시그니처**: `` `<에러 메시지>` @ `<path>:<line>` ``
- **수정 내용**: `<path>` — <1줄 요약>
- **dev server**: 사용자가 `pnpm run dev`로 재검증 필요 (스킬은 자동 재실행 안 함)
- **커밋 제안**: `<제안 메시지>` — (Y/수정/n)

*분할 + push 경로 진입 시 위 항목 아래에 추가*:
- **pre-staged 커밋**: `<hash>` <메시지>
- **fix 커밋**: `<hash>` <메시지>
- **push**: `origin/<branch>` 완료

## 케이스 2. 환경·설정·외부 서비스 문제 (수정 없음)
제목: `## ⚠️ 코드 수정 아님`
본문 항목:
- **원인 분류**: 환경 / 설정 / 외부 API·서비스 중 하나
- **증거**: `.check-runtime/runtime.log`의 관련 라인 요약
- **다음 액션**: 환경변수 확인 / 의존성 재설치 / 외부 서비스 상태 점검 등 구체 지시

## 케이스 3. 원인 불명확 (수정 보류)
제목: `## ⏸ 분석 불명확, 수정 보류`
본문 항목:
- **로그 요약**: `.check-runtime/runtime.log`의 시그니처 + 주변 context
- **추정 후보**: 1) ... 2) ... (최대 3개)
- **다음 액션**: 사용자 확인 후 스킬 재호출 또는 수동 수정

## 케이스 4. dev server 아직 실행 중 (로그 finalize 안 됨)
제목: `## ⏸ dev server 종료 필요`
본문 항목:
- **상태**: `.check-runtime/`이 아직 finalize되지 않음 (`meta.txt`의 `ended_at` 없음)
- **원인 후보**: 클라이언트 전용 에러라 터미널 로그에 안 남음 / `VIBE_DEV_NO_AUTOKILL=1`로 auto-kill 비활성화 / auto-kill 감지 패턴 miss
- **다음 액션**: 에러 확인 후 `Ctrl+C`로 dev server 종료 → 스킬 재호출

## 케이스 5. Pre-flight 실패로 커밋 제안 생략
제목: `## ⏸ 커밋 제안 생략`
본문 항목:
- **이유**: git user.name/email 미설정 / merge·rebase·cherry-pick·revert 진행 중 중 하나
- **다음 액션**: 구체 명령

## 리포트 금지
- 리포트 외 장황한 설명 출력 금지
- 환경 문제를 코드 수정으로 억지 해결하려는 제안 금지
- 본 스킬 범위 밖 리팩터링·성능 개선 제안 금지

# 금지 사항
- `.check-runtime/` 없이 수정 시작 금지
- 과거 로그 기반 수정 금지
- 환경 문제를 코드 수정으로 억지 해결 금지
- 같은 오류에 대해 반복 수정 금지
- 사용자 확인 없이 `git commit` 실행 금지
- 커밋 메시지에 Co-Authored-By 또는 Claude 언급 포함 금지
- `git push` 자동 실행 금지
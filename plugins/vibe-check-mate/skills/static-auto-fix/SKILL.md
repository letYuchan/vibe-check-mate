---
name: static-auto-fix
description: 최신 .check-static 상태를 기반으로 lint/typecheck 오류를 최소 수정으로 해결한다.
---

# 목적
.check-static에 기록된 최신 정적 분석 실패 상태를 기반으로, 관련 파일만 최소 수정하여 lint 및 typecheck 오류를 해결한다.

# 입력
- .check-static/lint.log
- .check-static/typecheck.log
- .check-static/error-files.txt

# 전제
- .check-static은 항상 최신 check 실행 결과를 의미한다.
- stale 상태의 .check-static을 신뢰하지 않는다.
- 이 스킬은 항상 fresh 상태를 기준으로 동작해야 한다.

# 스크립트 존재 확인 및 권한 설정
1. scripts/run-static-check-with-logs.sh 존재 여부를 확인한다.
2. 없으면 생성한다.
3. 항상 실행 권한을 보장한다:

chmod +x scripts/run-static-check-with-logs.sh

# 절차 (각 종료 지점은 반드시 리포트 케이스와 매핑)
1. 반드시 먼저 `pnpm run check`를 실행해 현재 상태 기준으로 `.check-static`을 최신화한다.
2. 초기 check 통과 → **케이스 3 리포트** (이유: "이미 통과, 수정할 것 없음") 후 종료.
3. 초기 check 실패 → `.check-static`을 최신 실패 상태로 간주.
4. `error-files.txt`에 포함된 파일만 수정 대상으로 제한한다.
5. 에이전트를 사용해 lint/typecheck 오류만 최소 수정으로 해결한다.
6. 수정 후 반드시 `pnpm run check`를 다시 실행한다.
7. 재검증 통과 → **케이스 1 리포트** 출력 후 "커밋 제안" 단계 진입.
   - 커밋 제안 중 Pre-flight 실패 → 케이스 1 리포트는 이미 출력된 상태에서 **케이스 4 리포트도 추가 출력**.
8. 재검증 실패 → **케이스 2 리포트** 후 종료 (`.check-static` 유지).

# 수정 규칙
- .check-static/error-files.txt에 없는 파일은 절대 수정하지 않는다.
- lint/typecheck 오류 해결과 직접 관련된 수정만 수행한다.
- refactor 금지
- 네이밍 변경 금지. 단, 오류 해결에 필요한 경우만 예외로 허용한다.
- 새로운 파일 생성 금지
- 테스트 코드 수정 금지. 단, 로그에 직접 근거가 있고 명시적으로 필요한 경우만 예외로 허용한다.
- 프로젝트 전체 탐색 금지
- 최소 수정만 수행한다.

# 에이전트 실행 규칙
- 최신 `.check-static`를 단일 source of truth로 사용한다.
- 추가적인 프로젝트 전체 lint/typecheck 실행 금지
- 로그에 직접 근거가 있는 수정만 수행한다.
- 불필요한 개선, 정리, 구조 변경 작업 금지
- 반복 수정 루프 금지
- **bash 명령을 `;`로 여러 개 chain 금지** — 마지막 명령의 exit code만 반환되므로 check 성공 여부를 잘못 판단하게 됨. 필요하면 `if pnpm run check; then ... fi` 패턴 또는 개별 tool call로 분리.
- 재검증용 bash는 `pnpm run check`만 단독 실행해 exit code를 명확히 관찰.

# 리포트 (필수)
**모든 종료 지점에서 반드시 케이스 1~4 중 정확히 하나의 리포트를 출력한다. 침묵 exit 절대 금지.**
수정 성공 후 커밋 제안 단계에서 Pre-flight가 실패하면 **케이스 1 + 케이스 4 리포트 2개**를 모두 출력한다 (수정 자체는 성공, 커밋만 스킵됐음을 명확히).

케이스별로 정해진 구조로 사용자에게 알린다. 리포트는 tight하게 — 본 스킬 범위 밖 조언·자화자찬 금지.

## 케이스 1. 수정 성공 + check 통과
제목: `## ✅ static check 통과`
본문 항목:
- **수정 대상**: `error-files.txt` 범위에서 실제 수정된 파일 목록
- **해결된 에러**: 각 항목 `` `<path>:<line>` — <에러코드/규칙명> : <1줄 근거> ``
- **검증**: `pnpm run check` 재실행 → 통과, `.check-static/` 제거됨
- **커밋 제안**: `<제안 메시지>` — (Y/수정/n)

*분할 + push 경로 진입 시 위 항목 아래에 추가*:
- **pre-staged 커밋**: `<hash>` <메시지>
- **fix 커밋**: `<hash>` <메시지>
- **push**: `origin/<branch>` 완료

## 케이스 2. 수정 시도 후 check 여전히 실패
제목: `## ❌ 수정 후에도 check 실패`
본문 항목:
- **수정한 파일**: 목록
- **남은 에러 요약**: 상위 2~3개 (path:line + 규칙/코드)
- **다음 액션**: 사용자 수동 수정 필요, `.check-static/` 최신 로그 경로 안내

## 케이스 3. 수정 생략
제목: `## ⏸ 수정 생략`
본문 항목:
- **이유**: `error-files.txt` 비어있음 / 범위 밖 수정 필요 / 분석 불명확 / stale 상태 의심 중 하나
- **현재 상태**: `.check-static/` 유지, working tree 변경 없음
- **다음 액션**: 사용자가 해야 할 구체적 일

## 케이스 4. Pre-flight 실패로 커밋 제안 생략
제목: `## ⏸ 커밋 제안 생략`
본문 항목:
- **이유**: git user.name/email 미설정 / merge·rebase·cherry-pick·revert 진행 중 중 구체적 하나
- **다음 액션**: 구체 명령 (예: `git config --global user.email "..."`)

## 리포트 금지
- 리포트 외 장황한 설명·해설 출력 금지
- 본 스킬 범위 밖 refactor/스타일/구조 제안 금지
- 수정하지 않은 파일까지 언급 금지
- 수정이 불가능하거나 불명확한 경우에도 케이스 2 또는 3 포맷으로 보고 (침묵 금지)

# 종료 조건
- check 통과 시 아래 "커밋 제안" 단계로 진행.
- check 실패 시 종료한다. 추가 반복 금지
- 동일한 실패 상태가 반복되면 즉시 종료한다.

# 커밋 제안 (check 통과 시)
check가 통과했을 때만 커밋을 제안한다. 자동 커밋은 하지 않는다 — 반드시 사용자 확인을 받는다.

## Pre-flight 검사
1. **git 정체성 확인**: `git config user.name`, `git config user.email` 둘 다 비어있지 않아야 한다. 비면 "git user.name/email을 먼저 설정해 주세요" 안내 후 제안 중단.
2. **git 진행 상태 확인**: `.git/MERGE_HEAD`, `.git/REBASE_HEAD`, `.git/CHERRY_PICK_HEAD`, `.git/REVERT_HEAD` 중 하나라도 존재하면 안내 후 제안 중단.
3. **스테이징 감지 → 분기**: `git diff --cached --name-only`가 비어있지 않으면 block하지 말고 아래 **"스테이징 충돌 시 자동 분할 + push"** 경로로 분기.

## 제안 절차 (pre-flight 통과 시에만)
1. 커밋 대상 파일을 3조건 **모두** 만족하는 파일로 좁힌다:
   - (a) `.check-static/error-files.txt`에 포함
   - (b) `git diff --name-only HEAD` 결과에 포함 (실제 수정됨)
   - (c) untracked 아님 (`git ls-files --error-unmatch <file>`)
2. 좁혀진 파일 목록과 diff 요약을 보여준다.
3. Conventional Commits 스타일 메시지를 생성한다:
   - lint만 수정 → `style: fix lint violations in <scope>`
   - typecheck만 수정 → `fix: resolve type errors in <scope>`
   - 둘 다 수정 → `fix: resolve lint and type errors in <scope>`
4. "이 메시지로 커밋할까요? (Y / 메시지 수정 / n)" 형식으로 확인한다.
5. 응답 처리:
   - **Y**: `git add <좁혀진 파일 목록>` → `git commit -m "<제안 메시지>"`
   - **메시지 수정**: 사용자가 준 메시지로 커밋
   - **n**: 커밋하지 않고 working tree를 유지한 채 종료

## 스테이징 충돌 시 자동 분할 + push (Pre-flight 3번 진입)
기존 스테이지된 변경이 존재하면 중단하지 않고 아래 절차로 **커밋 2개 분할 + push 자동 실행**.

1. **pre-stage 메시지 생성**: `git diff --cached`로 변경 성격 분석 → Conventional Commits prefix 추론 (`docs/` → `docs:`, `*.test.*` → `test:`, 설정 파일 → `chore:`, 그 외 → `refactor:` / `chore:`) → 1줄 메시지 작성.

2. **fix 메시지 생성**: 기존 제안 절차의 로직 그대로 (lint/typecheck 분류에 따라 `style:` / `fix:`).

3. **단일 통합 제안** — 두 메시지를 한 번에 보여주고 단일 게이트:
   ```
   ## 🗂 커밋 분할 + push 제안
   
   [1/2 pre-staged] <메시지1>
   [2/2 fix]        <메시지2>
   
   승인 시 위 순서로 커밋 후 git push 실행. (Y / 수정1 / 수정2 / n)
   ```

4. **응답 처리**:
   - **Y** → `git commit -m "<1>"` (pre-stage는 이미 staged) → `git add <fix 좁혀진 목록>` → `git commit -m "<2>"` → `git push`
   - **수정1** / **수정2** → 해당 메시지만 교체해 재확인 → Y
   - **n** → 아무것도 실행하지 않고 종료 (stage·working tree 모두 유지)

5. **push 실패 시** (네트워크·permission·no upstream 등): 케이스 2 리포트로 전환해 이유 전달, 커밋 2개는 로컬에 남김.

## 커밋 규칙
- Co-Authored-By 추가 금지 (Claude 포함 어떤 공저자도 넣지 않는다)
- prefix는 feat / fix / refactor / style / docs / test / chore / merge 중 의미에 맞는 것
- 간결·명확한 메시지
- `git push`는 **기본 자동 실행하지 않는다**. 예외: 분할 경로에서 사용자가 Y 게이트로 명시 승인한 경우만 자동 push.
- `git add -A`나 `git add .` 금지 — 반드시 좁혀진 파일 목록만 명시적으로 스테이징. 분할 경로에서도 동일 (pre-stage는 이미 staged 상태 그대로 유지).

## 커밋 제안 생략 조건
- check가 여전히 실패하면 제안 자체를 하지 않는다
- pre-flight 1·2번(git 정체성, 진행 상태) 중 하나라도 실패하면 제안하지 않는다 (스테이징 충돌은 더 이상 block 사유 아님)
- 좁혀진 파일 목록이 비어있으면(= 실제 수정이 없었음) 제안하지 않는다
- `error-files.txt` 밖 파일이 수정됐다면 이유 보고 후 종료

# 금지 사항
- stale .check-static을 기반으로 수정 시작 금지
- .check-static을 누적 로그 저장소로 사용하는 것 금지
- error-files 범위를 넘어선 수정 금지
- 다단계 자동 수정 루프 생성 금지
- 정적 분석 오류와 무관한 런타임 문제를 이 스킬에서 처리하려고 시도하는 것 금지
- 사용자 확인 없이 `git commit` 실행 금지
- 커밋 메시지에 Co-Authored-By 또는 Claude 언급 포함 금지
- `git push` 자동 실행 금지

# 설계 원칙
- always check → fix → check
- .check-static은 최신 실패 상태만 의미한다
- 검증은 deterministic, 수정은 constrained
- 에이전트는 상태 기반으로만 동작한다
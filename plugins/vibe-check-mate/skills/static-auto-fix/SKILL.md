---
name: static-auto-fix
description: Use automatically when .check-static/AGENT_ACTION_REQUIRED.md exists, when pre-commit fails, or when .check-static logs exist. Fix lint/typecheck errors with minimal edits.
---

# 목적
.check-static에 기록된 최신 정적 분석 실패 상태를 기반으로, 관련 파일만 최소 수정하여 lint 및 typecheck 오류를 해결한다.

# 입력
- .check-static/lint.log
- .check-static/typecheck.log
- .check-static/error-files.txt
- .check-static/AGENT_ACTION_REQUIRED.md

# 전제
- .check-static은 항상 최신 check 실행 결과를 의미한다.
- stale 상태의 .check-static을 신뢰하지 않는다.
- 이 스킬은 항상 fresh 상태를 기준으로 동작해야 한다.
- `.check-static/AGENT_ACTION_REQUIRED.md`는 자동화 트리거이자 completion blocker다.
- `.check-static/AGENT_ACTION_REQUIRED.md`가 존재하면 다른 작업보다 먼저 이 스킬을 실행한다.
- action file에는 짧은 handoff만 있고, 상세 절차는 이 SKILL.md를 따른다.
- `runtime-auto-fix`의 static gate 실패로 호출된 경우는 **runtime-handoff mode**다.
- runtime-handoff mode에서는 static 수정 성공 후 커밋 계획을 제안하지 않고, runtime-auto-fix로 돌아가 clean dev restart를 다시 수행한다.

# 스크립트 존재 확인 및 권한 설정
1. scripts/run-static-check-with-logs.sh 존재 여부를 확인한다.
2. 없으면 생성한다.
3. 항상 실행 권한을 보장한다:

chmod +x scripts/run-static-check-with-logs.sh

# 절차 (각 종료 지점은 반드시 리포트 케이스와 매핑)
1. `.check-static/AGENT_ACTION_REQUIRED.md`가 있으면 반드시 먼저 읽는다.
2. `.check-static/lint.log`를 읽는다.
3. `.check-static/typecheck.log`를 읽는다.
4. `.check-static/error-files.txt`를 읽는다.
5. 수정 전 git snapshot을 기록한다:
   - `.check-static/git-before-status.txt` ← `git status --short`
   - `.check-static/git-before-staged.txt` ← `git diff --cached --name-only`
   - `.check-static/git-before-working.txt` ← `git diff --name-only`
6. 반드시 `pnpm run check`를 실행해 현재 상태 기준으로 `.check-static`을 최신화한다.
7. 초기 check 통과:
   - standalone mode → **케이스 3 리포트** (이유: "이미 통과, 수정할 것 없음") 후 종료.
   - runtime-handoff mode → 수정 없이 runtime-auto-fix로 복귀. 사용자에게 최종 commit/push 제안을 하지 않는다.
8. 초기 check 실패 → `.check-static`을 최신 실패 상태로 간주한다.
9. `error-files.txt`에 포함된 파일만 수정 대상으로 제한한다.
10. lint/typecheck 오류만 최소 수정으로 해결한다.
11. 수정 후 반드시 `pnpm run check`를 다시 실행한다.
12. 재검증 통과:
   - standalone mode → **케이스 1 리포트** 출력 후 "커밋 계획 + push 제안" 단계 진입.
   - runtime-handoff mode → **케이스 5 리포트**를 내부 handoff 결과로 사용하고 runtime-auto-fix로 복귀. 사용자에게 최종 commit/push 제안을 하지 않는다.
   - 커밋 제안 중 Pre-flight 실패 → 케이스 1 리포트는 이미 출력된 상태에서 **케이스 4 리포트도 추가 출력**.
13. 재검증 실패 → **케이스 2 리포트** 후 사용자에게 `계속 수정할까요? (Y / N)` 질문.
14. 사용자가 `Y`를 선택하면 `pnpm run check`로 최신 `.check-static`을 재생성하고 다음 attempt를 시작한다.
15. 사용자가 `N`을 선택하면 `.check-static/AGENT_ACTION_REQUIRED.md`를 유지하고 종료한다.

# 수정 규칙
- .check-static/error-files.txt에 없는 파일은 절대 수정하지 않는다.
- `.check-static/AGENT_ACTION_REQUIRED.md`를 무시하고 완료 보고하지 않는다.
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
- 지속적으로 비슷한 오류가 발생하면, 반드시 다음 수정 전에 다른 방법과 접근법을 먼저 생각하고 전략을 바꾼다.
- **bash 명령을 `;`로 여러 개 chain 금지** — 마지막 명령의 exit code만 반환되므로 check 성공 여부를 잘못 판단하게 됨. 필요하면 `if pnpm run check; then ... fi` 패턴 또는 개별 tool call로 분리.
- 재검증용 bash는 `pnpm run check`만 단독 실행해 exit code를 명확히 관찰.

# retry 정책

- 기본 attempt는 1회다.
- 실패 시 반드시 사용자에게 `계속 수정할까요? (Y / N)`를 묻는다.
- `Y`면 최신 source of truth를 다시 생성한다:
  - `pnpm run check`
  - `.check-static/lint.log`
  - `.check-static/typecheck.log`
  - `.check-static/error-files.txt`
- 같은 오류가 반복되면 같은 수정 전략을 반복하지 않는다.
- 같은 오류가 2회 이상 반복되면 다음 attempt 전에 원인 가설과 다른 접근법을 먼저 짧게 정리한다.
- `N`이면 action file을 유지하고 리포트한다.

# 리포트 (필수)

아래 종료 케이스에 해당하는 템플릿을 정확히 복사해서 출력한다. 기본은 정확히 하나이며, 수정 성공 후 Pre-flight가 실패한 경우만 케이스 1 뒤에 케이스 4를 추가한다. 제목, 항목명, 순서, 빈 줄, 선택지 표기를 바꾸지 않는다. 해당 없는 값은 `없음`으로 채운다. 로그 전문을 붙이지 않는다.

수정 성공 후 Pre-flight가 실패하면 케이스 1을 먼저 출력하고, 이어서 케이스 4를 그대로 추가 출력한다.

## 케이스 1. 수정 성공 + check 통과

```md
## ✅ static fix verified

- **attempts**: <number>
- **수정 대상**: <files or 없음>
- **해결된 에러**: <path:line — rule/code : reason; ...>
- **검증**: pnpm run check 재실행 → 통과
- **정리**: .check-static/ 제거됨
- **commit plan**:
  - [1/N existing] <message or 없음>
  - [2/N development] <message or 없음>
  - [N/N static-fix] <message>
- **주의**: final-green split. 일부 중간 커밋은 단독 green이 아닐 수 있음.
- **push**: 승인 시 분할 커밋 후 git push
- **승인**: Y / 수정 / N
```

## 케이스 2. 수정 시도 후 check 여전히 실패

```md
## ❌ static fix not verified

- **attempts**: <number>
- **수정한 파일**: <files or 없음>
- **남은 에러 요약**: <top 2-3 errors>
- **검증**: pnpm run check 재실행 → 실패
- **상태**: .check-static/AGENT_ACTION_REQUIRED.md 유지
- **다음 액션**: 계속 수정할까요? (Y / N)
```

## 케이스 3. 수정 생략

```md
## ⏸ static fix skipped

- **이유**: <error-files.txt 비어있음 | 범위 밖 수정 필요 | 분석 불명확 | stale 상태 의심 | 이미 통과>
- **상태**: .check-static/ 유지, working tree 변경 없음
- **다음 액션**: <specific next action>
```

## 케이스 4. Pre-flight 실패로 커밋 제안 생략

```md
## ⏸ commit suggestion skipped

- **이유**: <git user.name/email 미설정 | merge/rebase/cherry-pick/revert 진행 중>
- **다음 액션**: <specific command>
```

## 케이스 5. runtime-handoff mode에서 static gate 수정 성공

```md
## ✅ static gate fixed for runtime

- **attempts**: <number>
- **수정 대상**: <files or 없음>
- **해결된 에러**: <path:line — rule/code : reason; ...>
- **검증**: pnpm run check 재실행 → 통과
- **handoff**: runtime-auto-fix로 복귀 → pnpm run dev clean restart 재검증
- **commit plan**: runtime-auto-fix의 runtime-fix bucket에 포함
```

## 리포트 금지
- 템플릿 밖 설명 추가 금지
- 항목명 변경 금지
- 선택지를 `Y / 수정 / N` 또는 `Y / N` 외 형태로 변경 금지
- 수정하지 않은 파일 언급 금지
- 로그 전문 출력 금지

# 종료 조건
- check 통과 시 아래 "커밋 계획 + push 제안" 단계로 진행한다.
- runtime-handoff mode에서 check 통과 시 commit/push 제안 없이 runtime-auto-fix로 복귀한다.
- check 실패 시 사용자에게 `계속 수정할까요? (Y / N)`를 묻는다.
- 사용자가 `N`을 선택하면 action file을 유지하고 종료한다.
- 동일한 실패 상태가 반복되면 전략 변경 없이 다음 수정을 시작하지 않는다.

# 커밋 계획 + push 제안 (check 통과 시)
check가 통과했을 때만 분할 커밋 계획을 제안한다. 사용자 `Y` 승인 전에는 commit/push하지 않는다.

기본 정책은 **final-green split**이다. 최종 HEAD가 검증 통과하면 개발 변경과 static fix 변경을 분리할 수 있다. 단, 중간 커밋 하나만 checkout했을 때는 실패할 수 있음을 리포트에 명시한다.

## Pre-flight 검사
1. **git 정체성 확인**: `git config user.name`, `git config user.email` 둘 다 비어있지 않아야 한다. 비면 "git user.name/email을 먼저 설정해 주세요" 안내 후 제안 중단.
2. **git 진행 상태 확인**: `.git/MERGE_HEAD`, `.git/REBASE_HEAD`, `.git/CHERRY_PICK_HEAD`, `.git/REVERT_HEAD` 중 하나라도 존재하면 안내 후 제안 중단.
3. **git snapshot 확인**: `.check-static/git-before-*.txt`를 기준으로 기존 staged/working 변경과 static fix 변경을 구분한다.

## 분할 기준

1. **existing bucket**: skill 시작 전 이미 staged 상태였거나, 사용자가 기존 변경으로 둔 파일.
2. **development bucket**: 이번 개발 작업의 주 변경. existing과 구분이 불명확하면 development로 분류한다.
3. **static-fix bucket**: `.check-static/error-files.txt`에 포함되고, fix attempt 이후 추가 변경된 tracked 파일.

같은 파일에 development 변경과 static-fix 변경이 섞이면 `same-file overlap`으로 표시한다.

- patch split이 명확하면 `git add -p` 또는 equivalent patch staging으로 분리 제안
- 명확하지 않으면 final-green split warning을 붙인다
- 사용자가 원하면 static fix를 development commit에 fold한다

## 제안 형식

```
## 🗂 static verification commit plan

[1/N existing]    <메시지>  # 있을 때만
[2/N development] <메시지>
[N/N static-fix]  <메시지>

검증: final HEAD `pnpm run check` 통과
주의: final-green split. 일부 중간 커밋은 단독 green이 아닐 수 있음.

승인 시 위 순서로 커밋 후 git push 실행. (Y / 수정 / N)
```

## 응답 처리

- **Y**:
  1. bucket별 파일/patch만 stage한다.
  2. 위 순서로 commit한다.
  3. `git push`를 실행한다.
- **수정**: 사용자가 준 메시지 또는 bucket 구성을 반영해 다시 제안한다.
- **N**: commit/push하지 않고 working tree를 유지한다.

## 메시지 생성

- existing: 변경 성격에 따라 `docs:` / `test:` / `chore:` / `refactor:`
- development: 기능 변경이면 `feat:`, 버그 수정이면 `fix:`, 구조 변경이면 `refactor:`
- static-fix:
  - lint만 수정 → `style: fix static lint violations`
  - typecheck만 수정 → `fix: resolve static type errors`
  - 둘 다 수정 → `fix: resolve static verification errors`

## 기존 staged 변경이 있는 경우

기존 staged 변경이 존재해도 중단하지 않는다. existing bucket으로 분리해서 통합 제안한다.

   ```
   ## 🗂 static verification commit plan
   
   [1/3 existing]    <메시지1>
   [2/3 development] <메시지2>
   [3/3 static-fix]  <메시지3>
   
   승인 시 위 순서로 커밋 후 git push 실행. (Y / 수정 / N)
   ```

## 커밋 규칙
- Co-Authored-By 추가 금지 (Claude 포함 어떤 공저자도 넣지 않는다)
- prefix는 feat / fix / refactor / style / docs / test / chore / merge 중 의미에 맞는 것
- 간결·명확한 메시지
- `git push`는 사용자 `Y` 승인 후에만 실행한다.
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
- 비슷한 오류가 반복되는데 같은 수정 전략을 재시도하는 것 금지
- 정적 분석 오류와 무관한 런타임 문제를 이 스킬에서 처리하려고 시도하는 것 금지
- 사용자 확인 없이 `git commit` 실행 금지
- 커밋 메시지에 Co-Authored-By 또는 Claude 언급 포함 금지
- 사용자 `Y` 승인 없이 `git push` 실행 금지

# 설계 원칙
- always check → fix → check
- .check-static은 최신 실패 상태만 의미한다
- 검증은 deterministic, 수정은 constrained
- 에이전트는 상태 기반으로만 동작한다

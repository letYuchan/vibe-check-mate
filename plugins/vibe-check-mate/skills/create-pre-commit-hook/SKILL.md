---
name: create-pre-commit-hook
description: pnpm + husky 기반으로 프로젝트의 lint와 typecheck를 커밋 전에 강제하고, 실패 시 최신 정적 분석 오류 상태를 .check-static/에 기록하는 pre-commit hook을 설정한다.
---

# 목적
커밋 전에 pnpm run check를 자동 실행해 lint 및 typecheck 실패 시 커밋을 차단한다.
실패 시 최신 정적 분석 오류 상태를 .check-static/에 기록하여 후속 static-auto-fix 스킬이 참조할 수 있도록 한다.

# 역할 정의
- pre-commit 훅은 검사 + 차단 + 로그 생성만 담당한다.
- 오류 수정은 pre-commit에서 자동 수행하지 않는다.
- AI 수정은 별도 스킬(static-auto-fix)을 통해 수행한다.
- `.check-static/AGENT_ACTION_REQUIRED.md`는 completion blocker다. 이 파일이 있으면 `static-auto-fix`를 먼저 실행해야 한다.

# 사전 조건
- pnpm, git, package.json이 존재한다.
- package.json에 `lint`와 `typecheck` 스크립트가 존재한다.
- scripts/run-static-check-with-logs.sh가 존재한다.

# 절차

## 1. husky 설치
pnpm add -D husky
pnpm dlx husky init

## 2. package.json scripts 추가
scripts:
  check: bash ./scripts/run-static-check-with-logs.sh

`lint`와 `typecheck`는 기존 프로젝트 설정을 사용한다. 없으면 임의로 추가하지 말고, 사용자가 먼저 정적 검사 도구를 설정하도록 안내한다.

## 3. 스크립트 실행 권한 설정
chmod +x scripts/run-static-check-with-logs.sh
chmod +x .husky/pre-commit

## 3-B. .gitignore 보정
`.gitignore`에 아래 항목이 없으면 기존 내용을 보존하고 누락 항목만 추가한다.

```gitignore
.check-static/
.check-runtime/
client-error-endpoint.json
```

기존 `.gitignore` 항목을 삭제하거나 재정렬하지 않는다.

## 4. .husky/pre-commit 설정
#!/bin/sh
pnpm run check || exit 1

# 상태 정의

실패 시:
.check-static/
  lint.log
  typecheck.log
  error-files.txt
  AGENT_ACTION_REQUIRED.md

성공 시:
.check-static 없음

# 검증
- bash -n scripts/run-static-check-with-logs.sh가 통과해야 한다.
- pnpm run check 실행 시 lint/typecheck가 통과하면 .check-static이 남지 않아야 한다.
- pnpm run check 실행 시 lint/typecheck가 실패하면 .check-static에 최신 로그와 AGENT_ACTION_REQUIRED.md가 생성되어야 한다.
- 실패 시 error-files.txt에는 실제 존재하는 프로젝트 파일만 들어가야 한다.
- git commit 시 오류가 있으면 커밋이 차단되어야 한다.
- 오류 수정 후 pnpm run check 실행 시 .check-static이 제거되어야 한다.
- setup 검증을 위해 프로젝트 소스에 일부러 lint/typecheck 오류를 주입하지 않는다.

# 금지 사항
- pre-commit에서 AI 수정 실행 금지
- .check-static에 로그 누적 금지
- .check-static을 히스토리 저장소로 사용하는 것 금지
- git commit --no-verify 기본 사용 금지
- lint/typecheck 없이 훅만 설정 금지
- pre-commit에서 테스트/빌드 실행 금지
- 기존 .gitignore 항목 삭제 또는 재정렬 금지

# 설계 원칙
- .check-static은 항상 최신 정적 분석 실패 상태만 의미한다.
- 검증은 deterministic, 수정은 별도 단계로 분리한다.
- pre-commit은 최소 품질 게이트 역할만 수행한다.

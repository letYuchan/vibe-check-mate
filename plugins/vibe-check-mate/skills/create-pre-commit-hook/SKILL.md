---
name: create-pre-commit-hook
description: pnpm + husky 기반으로 biome lint와 TypeScript typecheck를 커밋 전에 강제하고, 실패 시 최신 정적 분석 오류 상태를 .check-static/에 기록하는 pre-commit hook을 설정한다.
---

# 목적
커밋 전에 pnpm run check를 자동 실행해 lint 및 typecheck 실패 시 커밋을 차단한다.
실패 시 최신 정적 분석 오류 상태를 .check-static/에 기록하여 후속 static-auto-fix 스킬이 참조할 수 있도록 한다.

# 역할 정의
- pre-commit 훅은 검사 + 차단 + 로그 생성만 담당한다.
- 오류 수정은 pre-commit에서 자동 수행하지 않는다.
- AI 수정은 별도 스킬(static-auto-fix)을 통해 수행한다.

# 사전 조건
- pnpm, git, package.json이 존재한다.
- biome.json, tsconfig.json이 존재한다.
- scripts/run-static-check-with-logs.sh가 존재한다.

# 절차

## 1. husky 설치
pnpm add -D husky
pnpm dlx husky init

## 2. package.json scripts 추가
scripts:
  lint: biome lint .
  lint:fix: biome lint --write .
  typecheck: tsc --noEmit
  check: bash ./scripts/run-static-check-with-logs.sh

## 3. 스크립트 실행 권한 설정
chmod +x scripts/run-static-check-with-logs.sh
chmod +x .husky/pre-commit

## 4. .husky/pre-commit 설정
#!/bin/sh
pnpm run check || exit 1

# 상태 정의

실패 시:
.check-static/
  lint.log
  typecheck.log
  error-files.txt

성공 시:
.check-static 없음

# 검증
- pnpm run check 실행 시 lint/typecheck가 통과하면 .check-static이 남지 않아야 한다.
- pnpm run check 실행 시 lint/typecheck가 실패하면 .check-static에 최신 로그가 생성되어야 한다.
- git commit 시 오류가 있으면 커밋이 차단되어야 한다.
- 오류 수정 후 pnpm run check 실행 시 .check-static이 제거되어야 한다.

# 금지 사항
- pre-commit에서 AI 수정 실행 금지
- .check-static에 로그 누적 금지
- .check-static을 히스토리 저장소로 사용하는 것 금지
- git commit --no-verify 기본 사용 금지
- lint/typecheck 없이 훅만 설정 금지
- pre-commit에서 테스트/빌드 실행 금지

# 설계 원칙
- .check-static은 항상 최신 정적 분석 실패 상태만 의미한다.
- 검증은 deterministic, 수정은 별도 단계로 분리한다.
- pre-commit은 최소 품질 게이트 역할만 수행한다.
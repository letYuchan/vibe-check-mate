---
description: vibe-check-mate 하네스를 현재 프로젝트에 한 방으로 구성한다 (biome 설정 + husky pre-commit + dev runtime 캡처 + check 스크립트).
---

# vibe-check-mate · setup

아래 절차를 순서대로 수행하고 첫 실패 시점에 중단 후 보고한다.

## 1. 에셋 복사 — plugin → 프로젝트 루트
`${CLAUDE_PLUGIN_ROOT}`에서 현재 프로젝트 루트(`.`)로 복사:
- `scripts/run-static-check-with-logs.sh` → `./scripts/run-static-check-with-logs.sh`
- `scripts/dev-runtime.sh` → `./scripts/dev-runtime.sh`
- `biome-config/biome.base.json` → `./biome-config/biome.base.json`
- `biome-config/biome.react.json` → `./biome-config/biome.react.json`
- `biome-config/biome.strict.json` → `./biome-config/biome.strict.json`

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
  - dev 서버에서 런타임 에러 발생하면 → `runtime-auto-fix` 스킬 호출

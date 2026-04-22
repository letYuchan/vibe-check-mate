# vibe-check-mate

AI 보조 코딩(바이브코딩)으로 만든 코드를 **린트 + 타입체크 + 런타임 에러 로그 + AI 자동 수정** 루프로 감싸는 Claude Code 플러그인.

## 이름의 뜻
- **vibe check**: AI가 뽑아낸 코드의 "바이브"를 검증
- **check**: 린트 / 타입 / 런타임 세 축 모두 체크
- **mate**: AI가 pair mate로 자동 수정 도와줌 + checkmate로 에러 끝장냄

## 구성
- **4개 스킬** (`plugins/vibe-check-mate/skills/`): `setup-biome-config`, `create-pre-commit-hook`, `static-auto-fix`, `runtime-auto-fix`
- **2개 셸 스크립트** (`plugins/vibe-check-mate/scripts/`): `run-static-check-with-logs.sh`, `dev-runtime.sh`
- **3개 biome preset** (`plugins/vibe-check-mate/biome-config/`): `biome.base.json`, `biome.react.json`, `biome.strict.json`
- **1개 슬래시 커맨드** (`plugins/vibe-check-mate/commands/setup.md`): `/vibe-check-mate:setup` — 한 방 부트스트랩

## 한 방 설치 (GitHub)

Claude Code 안에서:
```
/plugin marketplace add letYuchan/vibe-check-mate
/plugin install vibe-check-mate@vibe-check-mate-marketplace
```

### 로컬 개발 모드
```
/plugin marketplace add /path/to/vibe-check-mate
/plugin install vibe-check-mate@vibe-check-mate-marketplace
```

## 한 방 세팅 (프로젝트 루트에서)

```
/vibe-check-mate:setup
```

실행 후 프로젝트에 추가되는 것:

| 구분 | 경로 |
|------|------|
| 정적 검사 래퍼 | `scripts/run-static-check-with-logs.sh` |
| dev 런타임 캡처 | `scripts/dev-runtime.sh` |
| biome preset | `biome-config/biome.{base,react,strict}.json` |
| biome 루트 설정 | `biome.json` (감지된 preset으로 `extends`) |
| pre-commit 훅 | `.husky/pre-commit` (`pnpm run check \|\| exit 1`) |
| package.json scripts | `lint`, `lint:fix`, `typecheck`, `check`, `dev`, `dev:raw` |
| devDependencies | `@biomejs/biome`, `husky` |

## 동작 원리

```
git commit ──► .husky/pre-commit ──► pnpm run check
                                          │
              실패 시 ◄────────────────────┤
              .check-static/lint.log       │
              .check-static/typecheck.log  │
              .check-static/error-files.txt│
                                          │
              성공 시 ────────────────────►│ .check-static/ 삭제 + commit 진행

pnpm run dev ──► scripts/dev-runtime.sh ──► pnpm run dev:raw (실제 서버) + tee
                                                 │
                                                 ▼
                                           .check-runtime/runtime.log
                                           .check-runtime/error-files.txt
                                           .check-runtime/meta.txt
```

## 자동 수정 워크플로우

| 상황 | 호출 스킬 | 입력 |
|------|-----------|------|
| 커밋이 lint/typecheck로 차단됨 | `static-auto-fix` | 최신 `.check-static/` |
| dev 서버에서 런타임 에러 발생 | `runtime-auto-fix` | 최신 `.check-runtime/` |

두 스킬 모두 해당 폴더의 **최신 실패 상태**만 단일 source of truth로 사용한다. 과거 로그·추측 컨텍스트·`error-files.txt` 밖 파일은 수정하지 않는다.

## 커밋 제안 플로우 (자동 커밋 아님)
두 fix 스킬은 수정이 성공(`pnpm run check` 통과 또는 런타임 에러 해결)하면 커밋을 **제안**한다. 자동으로 커밋하지 않는다.

1. 스킬이 Conventional Commits 스타일 메시지를 생성 (예: `fix: resolve type errors in src/<scope>`).
2. "이 메시지로 커밋할까요? (Y / 수정 / n)"으로 사용자에게 확인.
3. 응답:
   - **Y** → `git add <error-files 범위>` + `git commit -m "..."` (Co-Authored-By 없음)
   - **수정** → 사용자가 준 메시지로 커밋
   - **n** → working tree 유지한 채 종료

규칙:
- prefix는 `feat / fix / refactor / style / docs / test / chore / merge` 중 선택
- `git push`는 절대 자동 실행하지 않음
- `error-files.txt` 범위 밖 파일은 스테이징하지 않음

## 설계 원칙
- 검증은 deterministic, 수정은 constrained
- 최소 수정만 수행 — refactor / 네이밍 변경 / 새 파일 생성 금지
- `.check-static` / `.check-runtime`은 누적 로그가 아닌 "최신 실패 상태" 플래그 (성공 시 제거)
- pre-commit은 차단 + 로깅만, AI 수정은 별도 단계 (`static-auto-fix`)
- 런타임 문제와 정적 문제를 한 스킬에서 섞지 않음

## `.gitignore` 권장 (사용자 프로젝트에 추가)
```
.check-static/
.check-runtime/
```

## Changelog
### v0.1.1
- 셸 스크립트 `set -euo pipefail` 제거 → lint/typecheck 각각 실패해도 양쪽 로그가 모두 `.check-static/`에 남음
- 커밋 제안 전 Pre-flight 3중 검사 추가: `git config user.{name,email}` · merge/rebase/cherry-pick 진행 상태 · 스테이징 충돌
- Auto-commit scope 엄격화: `error-files.txt` + 실제 수정 + tracked, 3조건 교집합만 스테이징 (`git add -A` 금지)
- `runtime-auto-fix`에 HMR dev server Ctrl+C 안내 · SIGINT trap 추가
- 모든 종료 지점에서 리포트 케이스(1~N) 강제 출력 규칙 추가
- bash chaining(`;`) 금지 규칙 추가 (exit code 오판 방지)
- `biome.base.json` preset의 `linter.includes` 한 줄 포맷으로 수정 (biome self-check 통과)

### v0.1.0
- 초기 릴리스

## 호환성
- Claude Code (플러그인 지원 버전)
- Node.js 18+
- pnpm (기본), npm/yarn은 현재 미지원
- Biome 2.x
- TypeScript 5.x

## License
MIT — [LICENSE](./LICENSE)

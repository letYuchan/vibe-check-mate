# vibe-check-mate

> AI 보조 코딩에서 **가장 짜증나는 루프**를 자동화하는 Claude Code 플러그인.
> 린트·타입체크·런타임 에러를 정형 로그로 캡처하고, 스킬 한 줄이면 **범위 안에서만** 최소 수정 → 재검증 → 커밋 제안까지 한 번에.

[![MIT](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE) · [letYuchan/vibe-check-mate](https://github.com/letYuchan/vibe-check-mate)

---

## 이런 거 매일 반복하고 있지 않나요

> "수정은 **최소한**으로만 해주세요."
> "범위 밖 파일은 건드리지 마세요."
> "아니 왜 그 파일까지 고쳐요. 되돌려주세요."
> "다 고쳤다면서요? dev 서버 켜니까 `TypeError: Cannot read properties of null...`"
> "이 로그 드릴게요. 한 번만 더 봐줘요."

**바이브코딩의 현실** — AI가 "다 됐습니다!" 하고 자신 있게 말함. dev server 켜면 런타임 에러. 터미널 로그 복사. Claude에 붙여넣기. "이거 고쳐줘". AI가 엉뚱한 파일 3개 건드림. "범위만!" 다시 프롬프트. 커밋 찍으려고 하면 lint 실패. 또 복사. 또 프롬프트.

그 와중에 **AI가 혼자 판단해서 같은 수정을 여러 번 시도합니다.** 첫 시도 실패 → 다른 접근 → 또 실패 → 또 다른 접근. 에러 시그니처는 그대로인데 AI는 "이번엔 다를 것"이라며 루프를 돕니다. **토큰만 계속 녹음.**

**이 루프, 하루에 몇 번 돌리고 있는지 세어본 적 있나요?**

---

## 이 플러그인은 그 루프를 자동화합니다

```
/vibe-check-mate:setup
```

한 번으로 끝나는 부트스트랩:
- **husky pre-commit 훅** — 커밋 시도하면 `pnpm run check` 자동 실행
- **실패하면 `.check-static/`에 정형 로그 3파일** — `lint.log` / `typecheck.log` / `error-files.txt`
- **dev 래퍼** — 런타임 에러를 `.check-runtime/`에 동일 포맷으로 캡처
- **biome 프리셋** — 프로젝트 유형 감지 후 base/react/strict 자동 적용

이후 커밋이 막히거나 런타임 에러가 나면 Claude에게 딱 한 줄:

```
static-auto-fix 돌려줘
```

Claude가:
1. `.check-static/error-files.txt` **범위 안 파일만** 열어본다
2. 로그에 **근거 있는 수정만** 수행 — refactor · 네이밍 변경 · 새 파일 생성 **금지**
3. `pnpm run check`로 deterministic 재검증
4. **정형 리포트** 출력 — 어떤 에러를 어떤 근거로 어떻게 고쳤는지 path:line 단위
5. Conventional Commits 메시지 제안 — `(Y / 수정 / n)` 게이트

**로그 복붙 없음. "범위만 고쳐줘" 재입력 없음. 커밋 메시지 고민 없음.**

---

## 왜 이게 필요한가

AI 코딩은 **속도**를 주지만 **통제**를 잃습니다.

### 통제를 잃는 순간들
1. **범위 밖 수정** — 타입 하나 고쳐달라고 했는데 import 정리, 네이밍 변경까지 손댐
2. **로그 복붙 루프** — 터미널 에러 → 수동 복사 → 설명 다시 씀 → 붙여넣기 → 반복
3. **"다 됐습니다" 착시** — lint·tsc는 통과했는데 실제 실행하면 런타임 에러
4. **반복 수정 루프로 토큰 낭비** — 같은 에러에 다른 접근을 여러 번 시도. "이번엔 다를 것"이라며 돌다가 세션 토큰을 다 태움
5. **커밋 메시지 즉흥** — 매번 고민, 또는 AI가 쓴 `feat: improve code` 같은 공허한 메시지

### 기존 접근의 한계
| 접근 | 왜 부족한가 |
|------|-------------|
| 단순 린터/CI | 실패만 던지고 끝. AI에게 **피드백 루프를 연결해주지 않음** |
| 자동 포맷터 | 포맷만 고침. 타입·런타임은 안 건드림 |
| "프롬프트 잘 쓰세요" | 매 세션마다 "수정 최소화", "범위 밖 금지", "로그 읽고 근거 제시" **똑같은 지시 수동 반복** |

`vibe-check-mate`는 이 세 계층을 **한 번에** 묶습니다 —
- 셸 스크립트가 **deterministic**하게 실패를 캡처
- 스킬이 **constrained** 규칙으로 AI 수정 범위를 고정
- 커밋 제안이 **사용자 게이트**로 최종 통제권을 돌려줌

---

## 설치

```
/plugin marketplace add letYuchan/vibe-check-mate
/plugin install vibe-check-mate@vibe-check-mate-marketplace
```

### 로컬 개발 모드
```
/plugin marketplace add /path/to/vibe-check-mate
/plugin install vibe-check-mate@vibe-check-mate-marketplace
```

---

## 구성

| 자산 | 개수 | 역할 |
|------|------|------|
| Skills | 4 | `setup-biome-config` · `create-pre-commit-hook` · `static-auto-fix` · `runtime-auto-fix` |
| Commands | 1 | `/vibe-check-mate:setup` — 한 방 부트스트랩 |
| Shell scripts | 2 | `run-static-check-with-logs.sh` · `dev-runtime.sh` |
| Biome presets | 3 | base / react / strict |

---

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

pnpm run dev ──► scripts/dev-runtime.sh ──► pnpm run dev:raw + tee
                                                 │
                                                 ▼
                                           .check-runtime/runtime.log
                                           .check-runtime/error-files.txt
                                           .check-runtime/meta.txt
```

**`.check-*/`는 "지금 실패" 스냅샷만 의미합니다.** 누적 로그가 아님. 통과하면 삭제. 스킬은 항상 최신 상태만 신뢰.

---

## 자동 수정 워크플로우

| 상황 | 호출 스킬 | 입력 |
|------|-----------|------|
| 커밋이 lint/typecheck로 차단 | `static-auto-fix` | 최신 `.check-static/` |
| dev 서버 런타임 에러 | `runtime-auto-fix` | 최신 `.check-runtime/` |

### 수정 규칙 (양쪽 공통)
- `error-files.txt` 범위 밖 파일 수정 **금지**
- refactor · 네이밍 변경 · 새 파일 생성 **금지**
- 로그에 **직접 근거 있는** 수정만 허용
- **최대 1회 시도** — 실패 시 즉시 리포트하고 종료, 반복 루프 **절대 금지** (토큰 낭비 방지)
- 동일 에러 시그니처 반복 감지 시 즉시 종료

### 정형 리포트 예시
```
✅ static check 통과

수정 대상: src/user.ts, src/post.ts
해결된 에러:
  - src/user.ts:12 — TS2322 : string → number 타입 맞춤
  - src/post.ts:5  — biome noVar : var → const
검증: pnpm run check ✓
커밋 제안: fix: resolve lint and type errors in src/ — (Y / 수정 / n)
```

### 스테이징 충돌 시 — 자동 분할 + push
이미 stage된 작업이 있으면 중단하지 않고 2커밋으로 분할한 뒤 push까지 자동:
```
🗂 커밋 분할 + push 제안

[1/2 pre-staged] docs: update README
[2/2 fix]        fix: resolve type errors in src/user.ts

승인 시 위 순서로 커밋 후 git push 실행. (Y / 수정1 / 수정2 / n)
```

### Pre-flight 검사
커밋 제안 전 아래를 확인 — 실패 시 제안 생략 후 이유 보고:
1. `git config user.{name,email}` 설정 여부
2. merge / rebase / cherry-pick / revert 진행 중 아님

---

## 설계 원칙

- **Deterministic 검증, constrained 수정**
- `.check-*/`는 누적 로그가 아닌 **"최신 실패 상태" 플래그**
- pre-commit은 **차단 + 로깅**만, AI 수정은 별도 단계
- 런타임 문제와 정적 문제를 **한 스킬에 섞지 않음**
- 모든 종료 지점에서 **정형 리포트 강제 출력** (침묵 exit 금지)
- `git push`는 기본 금지. 분할 경로에서만 명시 승인 후 예외 허용

---

## 권장 `.gitignore`
```
.check-static/
.check-runtime/
```

---

## 호환성

- Claude Code (플러그인 지원 버전)
- Node.js 18+
- pnpm — 기본. npm/yarn/bun 현재 미지원
- Biome 2.x
- TypeScript 5.x

---

## Changelog

### v0.2.0
- **스테이징 충돌 시 자동 분할 + push 경로 추가** — 기존 staged 변경이 있어도 block하지 않고 2커밋 분할 + 단일 Y 게이트로 push 자동 실행
- **모든 종료 지점에 리포트 케이스 강제 매핑** — 성공 / 실패 / 스킵 / Pre-flight 실패 모두 정형 보고, 침묵 exit 금지
- **bash chaining `;` 금지 규칙** — 체인된 명령의 exit code 오판 방지
- **반복 수정 루프 방지** — 최대 1회 시도, 동일 에러 시그니처 반복 시 즉시 종료 (토큰 낭비 차단)
- `biome.base.json` preset의 `linter.includes` 포맷 self-check 통과
- README 재작성 — pain-point 중심 구성

### v0.1.1
- 셸 스크립트 `set -euo pipefail` 제거로 lint/typecheck 각각 실패해도 양쪽 로그 모두 `.check-static/`에 남음
- Pre-flight 3중 검사: git identity / rebase state / 스테이징 (v0.2.0에서 스테이징은 분기 경로로 변경)
- Auto-commit scope 엄격화 — `error-files.txt` + 실제 수정 + tracked, 3조건 교집합만 스테이징
- HMR dev server Ctrl+C 안내 + SIGINT trap

### v0.1.0
- 초기 릴리스

---

## License
MIT — [LICENSE](./LICENSE)

## Author
[letYuchan](https://github.com/letYuchan)

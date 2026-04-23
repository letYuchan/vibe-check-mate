---
name: setup-biome-config
description: 루트 biome-config 폴더를 기준으로 프로젝트 유형을 분석해 적절한 Biome preset(base/react/strict)을 선택하고, biome 설치 및 biome.json extends 설정을 적용한다.
---

# 목적
프로젝트를 분석해 적절한 Biome preset을 자동으로 선택하고, 루트 biome.json에 올바른 extends 구성을 적용한다.

# 전제
- 프로젝트 루트에 biome-config/ 폴더가 존재한다.
- biome-config/ 아래에 다음 파일이 존재한다:
  - biome.base.json
  - biome.react.json
  - biome.strict.json
- 사용자가 별도 지정하지 않으면 기본 preset은 biome.base.json 이다.

# 입력
- package.json
- tsconfig.json
- 프로젝트 디렉터리 구조
- biome-config/ 내부 preset 파일

# 분석 기준

## 1. React 계열 여부 판단
다음 중 하나 이상이면 React 계열로 판단한다.
- package.json에 react 또는 react-dom 존재
- package.json에 next, vite, @remix-run/*, react-native 존재
- 프로젝트에 .tsx 파일이 존재
- app/, pages/, src/app/ 등 React/Next 스타일 구조가 존재

## 2. Strict preset 필요 여부 판단
다음 중 하나 이상이면 strict 적용을 고려한다.
- 사용자가 엄격한 lint 규칙을 원한다고 명시
- 라이브러리/SDK/공용 패키지 성격이 강함
- 기존 biome 설정 또는 코드 스타일이 strict 지향적임
- 새 프로젝트이거나 코드베이스가 작아 규칙 강화 비용이 낮음

## 3. 기본 규칙
- React 여부가 불명확하면 react preset을 적용하지 않는다.
- Strict 여부가 불명확하면 strict preset을 적용하지 않는다.
- 확신이 없으면 biome.base.json만 적용한다.

# 적용 규칙

## case 1. 일반 TS/JS 프로젝트
루트 biome.json:
{
  "$schema": "https://biomejs.dev/schemas/2.2.0/schema.json",
  "extends": ["./biome-config/biome.base.json"]
}

## case 2. React 프로젝트
루트 biome.json:
{
  "$schema": "https://biomejs.dev/schemas/2.2.0/schema.json",
  "extends": ["./biome-config/biome.react.json"]
}

## case 3. Strict만 필요한 프로젝트
루트 biome.json:
{
  "$schema": "https://biomejs.dev/schemas/2.2.0/schema.json",
  "extends": ["./biome-config/biome.strict.json"]
}

## case 4. React + Strict 프로젝트
루트 biome.json:
{
  "$schema": "https://biomejs.dev/schemas/2.2.0/schema.json",
  "extends": [
    "./biome-config/biome.react.json",
    "./biome-config/biome.strict.json"
  ]
}

# 설치 및 설정 절차

## 1. biome 설치 확인
- package.json에 @biomejs/biome가 없으면 설치한다.
- 기본적으로 devDependency로 설치한다.

명령:
pnpm add -D @biomejs/biome

## 2. tsconfig 확인
- tsconfig.json이 있으면 그대로 사용한다.
- TypeScript 프로젝트인데 tsconfig.json이 없으면 생성 또는 사용자 확인 후 추가한다.
- JS 전용 프로젝트면 tsconfig.json은 필수가 아니다.

## 3. biome.json 생성 또는 갱신
- 루트 biome.json이 없으면 생성한다.
- 루트 biome.json이 있으면 기존 설정을 검토한다.
- 기존 biome.json에 커스텀 규칙이 있으면 함부로 덮어쓰지 않는다.
- 가능하면 extends만 병합한다.
- 기존 extends가 있으면 충돌 없이 유지 가능한지 먼저 판단한다.
- 명확히 판단이 안 되면 기존 사용자 설정을 우선 존중하고 필요한 최소 변경만 한다.

## 4. package.json scripts 보정
가능하면 다음 스크립트를 확인하고 없으면 추가한다.

scripts:
  lint: biome lint .
  lint:fix: biome lint --write .

# 수정 규칙
- biome-config 내부 preset 파일은 수정하지 않는다.
- 루트 biome.json과 package.json만 필요한 범위에서 수정한다.
- 기존 사용자 커스텀 설정을 불필요하게 제거하지 않는다.
- preset 선택 근거가 불명확하면 가장 보수적으로 biome.base.json을 사용한다.

# 검증
- 루트 biome.json이 존재해야 한다.
- biome.json의 extends가 biome-config 내부 preset을 정확히 참조해야 한다.
- @biomejs/biome가 devDependency로 설치되어 있어야 한다.
- React 프로젝트가 아니면 react preset을 적용하지 않아야 한다.
- 확신이 없으면 base preset만 적용해야 한다.
- lint, lint:fix 스크립트가 있거나 기존 동등한 스크립트가 유지되어야 한다.

# 금지 사항
- biome-config 폴더명을 추측으로 바꾸는 것 금지
- preset 파일 내용을 프로젝트별로 직접 덮어쓰는 것 금지
- React 여부가 불분명한데 react preset을 적용하는 것 금지
- 애매한데 strict preset까지 과하게 적용하는 것 금지
- 기존 biome.json을 무조건 덮어쓰는 것 금지
- 기존 package.json scripts를 불필요하게 삭제하는 것 금지

# 설계 원칙
- 기본값은 항상 base
- React는 증거가 있을 때만
- Strict는 필요성이 명확할 때만
- 기존 프로젝트 설정은 최대한 존중

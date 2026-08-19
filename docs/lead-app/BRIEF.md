# 리드 수집 웹앱 — 공유 브리프 (코디네이터 작성)

이 문서는 기획·개발·배포 3개 워커가 공유하는 단일 컨텍스트입니다. 각 워커는 작업 시작 전에 이 문서 전체와 `voucher.html`을 먼저 읽으세요.

## 배경

- `https://burwoodjoy.github.io/voucher.html` 은 OBLIV CLINIC × UH.SUITE 호텔 투숙객 전용 바우처 페이지(4개 언어: 한/영/중/일)이며, 최하단에 **리드 제출 폼**(이름 / 연락받을 메신저 / 메신저 ID·전화번호 / 국적)이 이미 구현되어 있다.
- 현재 폼은 받을 서버가 없어서 `voucher.html` 스크립트 상단의 `var LEAD_ENDPOINT = "";` 가 비어 있고, 제출 시 콘솔/localStorage에만 기록된다.
- 이번 프로젝트의 목표: **제출된 리드를 실제로 수집·보관하고, 마케터가 조회·관리할 수 있는 웹앱**을 만들어 배포한다.

## 기존 페이로드 계약 (voucher.html이 POST하는 JSON)

```json
{
  "name":        "홍길동",
  "messenger":   "whatsapp" | "line" | "wechat" | "kakaotalk",
  "contact":     "메신저 ID 또는 전화번호",
  "nationality": "KR|US|CN|JP|TW|HK|SG|TH|VN|RU|OTHER",
  "lang":        "ko" | "en" | "zh" | "ja",
  "source":      "voucher",
  "submittedAt": "2026-08-19T12:34:56.000Z"
}
```

voucher.html 폼 UI·i18n·검증 로직은 완성 상태이므로 **변경 최소화** — 제출 전송부(LEAD_ENDPOINT/fetch)만 새 API 설계에 맞게 손댄다.

## 인프라 제약 (중요 — 계획과 구현 모두 이 안에서만)

1. **정적 호스팅**: 이 레포가 곧 GitHub Pages 사이트다 (`main` 푸시 = 배포, `https://burwoodjoy.github.io`). 서버사이드 코드는 이 레포에서 실행 불가.
2. **DB/백엔드**: Supabase 프로젝트 **obliv-foreigner** 를 사용한다.
   - Project ref: `dqnjbheejjtoitrbzxmp` / Region: ap-northeast-2 (서울)
   - API Base URL: `https://dqnjbheejjtoitrbzxmp.supabase.co`
   - **워커는 Supabase에 직접 배포/접속 권한이 없다** (CLI 미설치·미인증). DB 마이그레이션 적용, Edge Function 배포, SQL 조회는 **코디네이터가 MCP로 수행**한다. 필요 시 `orca orchestration ask` 로 코디네이터에게 요청할 것.
3. **레포에 커밋 가능한 키**: Supabase **anon/publishable key만** (공개용으로 설계된 키). service_role 등 비밀키는 절대 금지.
4. **로컬 인증된 배포 수단**: GitHub(`gh`, git push)뿐이다. wrangler/vercel/netlify/supabase CLI는 설치되어 있지 않다.
5. Node v24 사용 가능. 로컬 정적 테스트는 `python3 -m http.server` 등 활용.

## 권장 아키텍처 방향 (기획 워커가 검토 후 확정)

- 수집: Supabase **Edge Function** (예: `submit-lead`) 또는 PostgREST 직접 insert 중 택1. CORS는 `https://burwoodjoy.github.io` 허용 필요.
- 저장: `leads` 테이블 + **RLS** — 익명(anon)은 INSERT만, SELECT/UPDATE는 인증된 관리자만.
- 관리자 인증: Supabase Auth 이메일+비밀번호. 조회 권한은 허용된 관리자 이메일로 제한 (마케터 이메일: `yh.jung@medibuilder.com`). 계정 가입(비밀번호 설정)은 사용자가 직접 한다 — 워커·코디네이터는 자격증명을 다루지 않는다.
- 관리자 대시보드: 이 레포 `admin/index.html` 정적 단일 파일 + supabase-js CDN. GitHub Pages로 함께 배포.

## 역할 분담 및 산출물 규약

| 단계 | 산출물 | 비고 |
|---|---|---|
| 기획 | `docs/lead-app/PLAN.md` | 코드 작성 금지(스키마 SQL 초안은 문서 내 허용) |
| 개발 | `supabase/migrations/0001_leads.sql`, (선택 시) `supabase/functions/submit-lead/index.ts`, `admin/index.html`, `voucher.html` 전송부 수정, `docs/lead-app/DEV-NOTES.md` | 로컬 커밋만, **푸시 금지** |
| 배포 | Supabase 반영(코디네이터에 ask) → `git push` → E2E 검증 → `docs/lead-app/DEPLOY-REPORT.md` | 유일하게 푸시 권한 있음 |

## CONFIG (코디네이터가 채움 — 개발 워커는 이 값을 사용)

아래 두 키 모두 **공개용으로 설계된 키**라 레포/클라이언트 코드에 넣어도 된다. 신규 코드에는 publishable 키를 우선 사용하되, 라이브러리/엔드포인트가 JWT 형식을 요구하는 경우에만 legacy anon 키를 사용.

- SUPABASE_URL: `https://dqnjbheejjtoitrbzxmp.supabase.co`
- SUPABASE_PUBLISHABLE_KEY: `sb_publishable_4z1mUiKCaP67VRYyjoGGig_9JukGA_1`
- SUPABASE_ANON_KEY (legacy JWT): `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRxbmpiaGVlamp0b2l0cmJ6eG1wIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA2MDYyNDUsImV4cCI6MjA5NjE4MjI0NX0.F-WqEyYH_pQ6cVs-9lD8nOjYtqlIfvdFknFBRE5FlQg`
- 참고: Edge Function을 verify_jwt=false로 배포하는 경우 함수 코드에서 CORS Origin 화이트리스트로 접근을 제한할 것.

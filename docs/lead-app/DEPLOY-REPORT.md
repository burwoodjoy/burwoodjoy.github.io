# 리드 수집 웹앱 — 배포 리포트 (DEPLOY-REPORT)

- 작성: 배포 워커 (task_f86d73aadcf6)
- 배포 일시: 2026-08-19 18:29 KST (커밋 `d330179` push → GitHub Pages build `built`)
- 선행 문서: [`BRIEF.md`](./BRIEF.md) · [`PLAN.md`](./PLAN.md) · [`DEV-NOTES.md`](./DEV-NOTES.md)

## 1. 배포된 URL

| 구성 요소 | URL | 상태 |
|---|---|---|
| 리드 폼 (투숙객용) | https://burwoodjoy.github.io/voucher.html | 라이브 — 새 전송부(Supabase REST 직접 INSERT) 서빙 확인 |
| 관리자 대시보드 (마케터용) | https://burwoodjoy.github.io/admin/ | 라이브 — HTTP 200 |
| 수집 API (PostgREST) | `POST https://dqnjbheejjtoitrbzxmp.supabase.co/rest/v1/leads` | 동작 — 201 확인 |
| DB | Supabase obliv-foreigner (ref `dqnjbheejjtoitrbzxmp`, ap-northeast-2) `public.leads` | 마이그레이션 적용 완료 |

Edge Function은 **없음**(PLAN §5.1 확정 — PostgREST 직접 insert). 배포된 서버 코드 0.

## 2. Supabase 반영 내역 (코디네이터가 MCP로 수행)

- `supabase/migrations/0001_leads.sql` 전체를 `apply_migration`으로 실행. 마이그레이션명은 Supabase에 **`create_leads_table_with_rls`** 로 기록됨(파일과 동일 내용, 이름만 다름).
- 적용 후 확인 조회 결과: `relrowsecurity = true`, 정책 3개 = `anon_insert_leads` / `admin_select_leads` / `admin_update_leads`, **DELETE 정책 없음**, 초기 0행.

## 3. 검증 결과표

### 3.1 배포·라이브 반영

| # | 항목 | 방법 | 결과 |
|---|---|---|---|
| V-1 | 로컬 커밋 리뷰 · 비밀키 유출 검사 | `git diff origin/main..HEAD` 전수 스캔 | **PASS** — publishable 키·legacy anon(JWT, `role=anon`) 키만 존재. `service_role`/`sb_secret` 등 비밀키 없음 |
| V-2 | GitHub Pages 빌드 | `gh api …/pages/builds/latest` | **PASS** — 커밋 `d330179` `built` |
| V-3 | `admin/` 라이브 | `curl -I` | **PASS** — HTTP 200 |
| V-4 | `voucher.html` 새 전송코드 반영 | `curl` 본문 확인 | **PASS** — `LEAD_ENDPOINT`(Supabase REST URL)·`SUPABASE_KEY`(publishable)·`submitted_at` 서빙 |

### 3.2 API E2E (curl, 라이브 인프라 대상 — 2026-08-19 18:31–18:33 KST)

| # | 시나리오 (PLAN §9 대응) | 기대 | 결과 |
|---|---|---|---|
| A-1 | 유효 리드 INSERT (`E2E-TEST-deploy 배포검증`, whatsapp/KR/ko) — E2E-1 상당 | 201 | **PASS** — `HTTP/2 201`. 코디네이터 SQL SELECT로 행 존재 확인(id=1, `created_at` 서버 시각 채워짐) → AC-1 |
| A-2 | enum 밖 값 POST (`messenger:"telegram"`) — E2E-3 | 4xx, 행 미생성 | **PASS** — `HTTP/2 400`(CHECK 위반), 행 미생성 확인 → AC-3 |
| A-3 | anon key로 SELECT — E2E-4 | 데이터 없음 | **PASS** — 빈 배열 `[]` (테이블에 2행 있던 시점에 조회) → AC-4 |
| A-4 | anon key로 DELETE 시도 | 삭제 불가 | **PASS** — 200이지만 영향 0행(DELETE 정책 없음). 직후 SQL SELECT에서 2행 그대로 존재 → RLS 차단 입증 |
| A-5 | 두 번째 유효 INSERT (`E2E-TEST-cors`, line/JP/ja — CORS 테스트 겸) | 201 | **PASS** — `HTTP/2 201`, SQL로 행 확인(id=3, `lang='ja'` 저장) |

- 테스트 행 정리: 코디네이터가 SQL로 `E2E-TEST%` 2행(id=1, 3) 삭제, 최종 `count(*) = 0` 확인. **테이블은 깨끗한 상태로 운영 시작.**
- 참고: `id=2`가 비어 있는 것은 400으로 거절된 A-2 시도가 identity 시퀀스만 소모한 정상 동작(행은 생성되지 않음). 운영 중 id에 간헐적 구멍이 보여도 이상이 아님.
- publishable 키가 게이트웨이에서 정상 수용됨(401 없음) — DEV-NOTES §1의 "legacy anon 키 교체" 시나리오는 **불필요했음**.

### 3.3 CORS (수집 API가 GitHub Pages origin에서 호출 가능한지)

| # | 항목 | 결과 |
|---|---|---|
| C-1 | `OPTIONS` preflight (`Origin: https://burwoodjoy.github.io`, `Access-Control-Request-Method: POST`, request-headers: `content-type,apikey,authorization,prefer`) | **PASS** — 200, `access-control-allow-origin: *`, 요청한 4개 헤더 전부 `access-control-allow-headers`로 허용, POST 허용, `max-age: 3600` |
| C-2 | `POST` + Origin 헤더 | **PASS** — 201, 응답에 `access-control-allow-origin: https://burwoodjoy.github.io` 에코 |

→ 브라우저에서 voucher.html 폼 제출이 CORS로 막히지 않음을 확인(PLAN §5.2 예측대로 추가 설정 불필요).

### 3.4 미실행 항목 — 사용자 수동 검증 필요 (로그인 필요 E2E)

관리자 계정(`yh.jung@medibuilder.com`)이 아직 생성되지 않아 **로그인이 필요한 E2E는 실행 불가**했다. 아래 §4-1 계정 생성 후 사용자가 직접 검증한다 (PLAN §9 표 참조):

| # | 시나리오 | 절차 |
|---|---|---|
| E2E-2 | 필수값 누락 제출 | voucher.html에서 일부 필드만 입력 후 제출 → 클라이언트 검증 오류, 네트워크 요청 없음 |
| E2E-5 | 잘못된 비밀번호 → 올바른 로그인 | `admin/` 접속, 오답 시 인라인 오류 → 정답 시 목록 최신순 표시 |
| E2E-6 | 상태 변경·메모 저장 → 새로고침 | new→contacted 변경, 메모 저장 후 새로고침해도 유지 |
| E2E-7 | 필터 조합 + CSV | 메신저/국적/상태 필터 AND 동작, CSV 엑셀에서 한글 정상(BOM) |
| E2E-8 | 375px 모바일 | 휴대폰에서 제출→관리 전 과정, 가로 스크롤 없음 |
| E2E-9 | 로그아웃 → 재접속 | 로그인 화면만 보이고 데이터 비노출 |

실 폼 제출 스모크(브라우저에서 voucher.html 제출 → 대시보드에서 보이는지)도 계정 생성 후 1회 권장.

## 4. 사용자가 직접 해야 할 남은 작업 (순서대로)

1. **관리자 계정 생성 (필수)** — Supabase Studio → Authentication → Users → **Add user** 로 `yh.jung@medibuilder.com` 계정과 비밀번호를 직접 생성한다(자동 확인(Auto Confirm) 옵션 사용 권장). 워커·코디네이터는 자격증명을 다루지 않는다(BRIEF 규약).
2. **Auth 설정 확인 (필수)** — 코디네이터 MCP로는 GoTrue 설정을 조회할 수 없어 미확인 상태다. Supabase Studio → **Authentication → Sign In / Providers → Email** 에서 ① Email provider **활성** ② **Confirm email ON** 을 확인한다. Confirm email이 꺼져 있으면 타인이 관리자 이메일로 위장 가입할 수 있으므로 반드시 ON(PLAN §6.2 전제).
3. **로그인 E2E 수행** — §3.4 표의 6개 항목. 전부 통과하면 실 손님 안내 시작 가능(PLAN §9 D-6).
4. (선택) 계정 생성 후 공개 회원가입 비활성화 — Studio에서 가능. 비활성화하지 않아도 RLS상 타 계정은 0건 조회이므로 선택 사항.
5. (운영) 스팸 발생 시 PLAN §6.4 승격 시나리오(Edge Function + 요율제한) 결정.

## 5. 참고 사항

- **Supabase 보안 어드바이저 기존 경고**: 이 프로젝트에 프로토타입 시절 함수 관련 경고(`handle_new_user`/`my_agency_id`/`my_role`/`rls_auto_enable` 등 SECURITY DEFINER 노출, leaked password protection 비활성)가 떠 있으나, **이번 `leads` 테이블·리드 앱과 무관한 기존 항목**이다. 정리 여부는 별도 판단.
- 요율제한 없음(위험 수용, PLAN §6.4). 목록은 최신순 1,000건 단일 요청(초과 시 페이지네이션 추가).
- 관리자 추가 방법: `0001_leads.sql` 하단 주석 — 정책 2개의 이메일 비교를 `in (...)`으로 바꾸는 후속 마이그레이션 1개.
- 리드 삭제는 API로 불가(정책 없음) — 필요 시 Supabase Studio SQL로만.

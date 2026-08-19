# 리드 수집 웹앱 — 개발 노트 (DEV-NOTES)

- 작성: 개발 워커 (task_324ba87e4734)
- 작성일: 2026-08-19
- 선행 문서: [`BRIEF.md`](./BRIEF.md) · [`PLAN.md`](./PLAN.md) — 본 문서는 구현 결과와 배포 담당자가 해야 할 일을 기록한다.

## 1. 구현 요약

PLAN §5.1 확정대로 **PostgREST 직접 insert** 방식으로 구현했다. **Edge Function은 만들지 않았다**(`supabase/functions/` 없음 — PLAN §8 "Edge Function은 만들지 않는다"). 서버 코드 0, 정적 파일 + 마이그레이션 1개가 전부다.

| 산출물 | 내용 |
|---|---|
| `supabase/migrations/0001_leads.sql` | `public.leads` 테이블(CHECK 제약 = 서버측 검증) + `created_at desc` 인덱스 + RLS(anon INSERT만 / 관리자 이메일만 SELECT·UPDATE / DELETE 정책 없음) |
| `voucher.html` (수정) | 전송부만 변경: `LEAD_ENDPOINT`를 Supabase REST URL로 설정, `SUPABASE_KEY` 상수 추가, fetch에 `apikey`/`Authorization`/`Prefer: return=minimal` 헤더 추가, payload 키 `submittedAt`→`submitted_at`. 폼 UI·검증·i18n·성공 화면은 무변경(AC-9). `LEAD_ENDPOINT`를 비우면 기존 콘솔/localStorage 테스트 모드로 동작하는 fallback도 유지 |
| `admin/index.html` (신규) | 정적 단일 파일 대시보드. supabase-js v2 CDN(jsdelivr) + Google Fonts만 사용. 로그인 / 요약 칩(클릭=상태 필터) / 필터 3종(메신저·국적·상태, AND) + 이름·연락처 검색 / 최신순 카드 리스트(연락처 탭=클립보드 복사, WhatsApp `wa.me` 링크, KST 표기) / 상태 변경(즉시 PATCH, 실패 시 원복+토스트) / 메모 저장(실패 시 입력값 유지) / CSV 내보내기(필터 반영, UTF-8 BOM, `leads_YYYYMMDD.csv`) / 로딩·빈목록·오류 상태 화면 / 새로고침 버튼. 골드/블랙 토큰은 voucher.html §7.1 그대로 |

### 주요 구현 결정

1. **API 키: publishable 키를 기본값으로 사용** (BRIEF CONFIG "신규 코드에는 publishable 키 우선" 규약).
   - `voucher.html`: `apikey` + `Authorization: Bearer` 둘 다 `SUPABASE_KEY`(publishable) 사용.
   - `admin/index.html`: `supabase.createClient(URL, SUPABASE_KEY)` — 로그인 후에는 supabase-js가 `Authorization`을 세션 JWT로 자동 교체하므로 RLS의 `authenticated` 정책이 적용된다.
   - **만약 E2E에서 401이 나면**(게이트웨이가 publishable 키를 거부하는 경우): 두 파일의 `SUPABASE_KEY` 상수를 BRIEF CONFIG의 legacy anon(JWT) 키로 교체하면 된다. 교체 위치는 정확히 2곳 — `voucher.html`의 `var SUPABASE_KEY = ...`, `admin/index.html`의 `var SUPABASE_KEY = ...`(주석으로 legacy 키가 이미 적혀 있음).
2. **`Prefer: return=minimal` 필수** — anon에게 SELECT 정책이 없으므로 `return=representation`이면 삽입 자체가 실패한다(PLAN §5.4). 코드에 이미 반영됨.
3. **wa.me 링크는 국가번호가 명시된 연락처만**(`+` 또는 `00` 시작) 링크화 — `010…` 같은 국내 표기를 잘못된 국가로 연결하는 것을 방지.
4. **상태 변경 후 카드가 현재 필터와 어긋나도 즉시 숨기지 않는다** — 조작 중 카드가 사라지는 UX 방지. 다음 필터 조작/새로고침 시 반영. 요약 칩 수는 즉시 갱신.
5. `admin/index.html`에 `<meta name="robots" content="noindex">` 추가(관리자 페이지 검색 노출 방지). 회원가입·비밀번호 재설정 UI는 PLAN대로 없음.
6. XSS 방어: 리드 데이터(이름·연락처·메모)는 전부 `esc()` 이스케이프 후 렌더링.

## 2. 로컬에서 수행한 검증

- `node --check`로 두 HTML의 인라인 `<script>` 전체 문법 검사 통과.
- `python3 -m http.server`로 `voucher.html`·`admin/index.html` 렌더 확인(Chrome): 콘솔 에러 0, 로그인 화면·폼 정상 표시, 375px 폭에서 가로 스크롤 없음.
- `voucher.html` diff가 전송부(주석 블록·상수·payload 키·fetch 헤더)에만 국한됨을 `git diff`로 확인(AC-9).
- SQL은 정적 검토만 수행(로컬에 Postgres 없음) — PLAN §4/§6.2 초안과 동일 구조.

## 3. 배포 담당자가 할 일 (순서대로)

PLAN §9의 체크리스트를 그대로 따르되, 구체 수단은 아래와 같다.

1. **마이그레이션 적용** — 워커는 Supabase 접근 불가. 코디네이터에게 `orca orchestration ask`로 요청:
   - `supabase/migrations/0001_leads.sql` **파일 전체 내용**을 MCP `apply_migration`(name: `0001_leads`)으로 실행.
   - 적용 후 확인 조회: `select relrowsecurity from pg_class where oid = 'public.leads'::regclass;` → `true`, `select polname from pg_policy where polrelid = 'public.leads'::regclass;` → 정책 3개.
2. **Edge Function 배포 없음** — 배포할 함수가 없다. `list_edge_functions`에 아무것도 추가되지 않는 것이 정상.
3. **Auth 설정 확인** (코디네이터 ask): 이메일/비밀번호 provider 활성 + **Confirm email ON**(타인 위장 가입 방지 — RLS 전제, PLAN §6.2).
4. **관리자 계정**: 사용자 본인이 Supabase Studio → Authentication → Users에서 `yh.jung@medibuilder.com` 생성(비밀번호 포함). 워커·코디네이터는 자격증명을 다루지 않는다.
5. `git push` (main = GitHub Pages 배포) → 반영 후 E2E.

## 4. 남은 검증 (라이브 인프라 필요 — 로컬에서 시도하지 않음)

PLAN §9 E2E-1~9 전체가 남아 있다. 아래는 배포 워커/코디네이터용 바로 실행 가능한 커맨드(치환: `$KEY` = publishable 키, 실패 시 legacy anon 키로 재시도).

```bash
KEY="sb_publishable_4z1mUiKCaP67VRYyjoGGig_9JukGA_1"
BASE="https://dqnjbheejjtoitrbzxmp.supabase.co/rest/v1/leads"

# (a) AC-1 스모크: 유효 INSERT → 201 기대
curl -si -X POST "$BASE" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" -H "Prefer: return=minimal" \
  -d '{"name":"E2E 테스트","messenger":"whatsapp","contact":"+82 10-0000-0000","nationality":"KR","lang":"ko","source":"voucher","submitted_at":"2026-08-19T00:00:00.000Z"}' | head -1

# (b) AC-3: enum 밖 값 → 4xx(CHECK 위반, 23514) 기대
curl -si -X POST "$BASE" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" -H "Prefer: return=minimal" \
  -d '{"name":"X","messenger":"telegram","contact":"x","nationality":"KR"}' | head -1

# (c) AC-4: anon SELECT → 데이터 없음(빈 배열 []) 기대
curl -s "$BASE?select=*" -H "apikey: $KEY" -H "Authorization: Bearer $KEY"

# (d) anon DELETE 시도 → 거부(또는 0행) 기대
curl -si -X DELETE "$BASE?id=eq.1" -H "apikey: $KEY" -H "Authorization: Bearer $KEY" | head -1
```

- 브라우저 E2E: 실 폼 제출(4개 언어 중 ko·en 각 1회), `admin/` 로그인(오답→정답), 상태 변경·메모 저장 후 새로고침 유지, 필터+CSV 엑셀 확인, 375px 확인, 로그아웃 후 재접속 — PLAN §9 표 그대로.
- (a)에서 넣은 테스트 행은 대시보드에서 `done` 처리하거나 Studio SQL로 삭제.

## 5. 알려진 한계 / 메모

- **요율제한 없음**(PLAN §6.4에서 위험 수용). 실제 스팸 발생 시 Edge Function 승격 시나리오 참고.
- 목록은 최신순 1,000건 단일 요청(PLAN §5.5). 초과 시 페이지네이션 추가 필요.
- supabase-js는 `@2` 최신(jsdelivr) 사용 — publishable 키(`sb_publishable_…`)는 supabase-js v2 최신에서 지원된다. 렌더 확인은 CDN 정상 로드 기준이며, CDN 차단 환경이면 로그인 카드에 라이브러리 로드 실패 안내가 뜬다.
- 관리자 추가 방법: `0001_leads.sql` 하단 주석 참고(정책 2개의 이메일 비교를 `in (...)`으로 바꾸는 후속 마이그레이션 1개).
- CSV는 필터된 행만 포함하며 Excel 호환을 위해 UTF-8 BOM + CRLF 사용.

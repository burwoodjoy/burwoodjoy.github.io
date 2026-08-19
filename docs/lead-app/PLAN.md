# 리드 수집 웹앱 — PRD / 설계 문서 (PLAN)

- 작성: 기획 워커 (task_7e397af78061)
- 작성일: 2026-08-19
- 선행 문서: [`docs/lead-app/BRIEF.md`](./BRIEF.md) — 인프라 제약·역할 분담은 브리프가 기준이며, 본 문서는 그 제약 안에서의 확정 설계다.
- 원칙: **과설계 금지.** 마케터 1인이 유지보수할 수 있는 최소 구성(정적 파일 2개 + 테이블 1개 + RLS 정책)만 확정한다.

---

## 1. 개요 · 목표

`https://burwoodjoy.github.io/voucher.html`(OBLIV CLINIC × UH.SUITE 투숙객 바우처, 4개 언어)의 최하단 리드 폼은 UI·검증·i18n이 완성돼 있으나 수신 서버가 없어 제출 데이터가 콘솔/localStorage에만 남는다(`voucher.html:1175`의 `var LEAD_ENDPOINT = "";`).

**목표**

1. 투숙객이 제출한 리드를 실제 DB(Supabase `obliv-foreigner`, ref `dqnjbheejjtoitrbzxmp`)에 저장한다.
2. 마케터가 로그인해서 리드를 조회·필터·상태관리·메모·CSV 내보내기 할 수 있는 관리자 대시보드(`admin/index.html`)를 같은 GitHub Pages로 배포한다.
3. voucher.html은 **제출 전송부(fetch 부분)만** 수정한다 — 폼 UI·검증·i18n은 손대지 않는다.

**성공 기준(요약)**: 실제 폰에서 폼 제출 → 수 초 내 대시보드에 리드가 최신순으로 보이고, 상태를 `new → contacted → done`으로 바꾸며 메모를 남기고, 필터된 목록을 CSV로 받을 수 있다. 익명 사용자는 어떤 방법으로도 리드를 조회할 수 없다.

## 2. 사용자 스토리

### 투숙객 (리드 제출)

- U1. 투숙객으로서, 바우처 페이지에서 이름·메신저·연락처·국적을 남기면 **성공 화면**(기존 `#leadSuccess`)을 보고 제출이 접수됐음을 확신하고 싶다.
- U2. 투숙객으로서, 전송이 실패하면(네트워크·서버 오류) 기존 다국어 오류 문구(`formSendError`)를 보고 **다시 제출**할 수 있어야 한다. 입력값은 사라지지 않는다.
- U3. 투숙객으로서, 한/영/중/일 어떤 언어로 제출해도 동일하게 접수되어야 하며, 내가 보던 언어(`lang`)가 함께 저장되어 그 언어로 연락받고 싶다.
- U4. 투숙객으로서, 내 개인정보는 예약 상담 목적 외에 노출되지 않아야 한다(익명 조회 불가).

### 마케터 (리드 관리) — `yh.jung@medibuilder.com`

- M1. 마케터로서, 이메일+비밀번호로 로그인해 **최신순** 리드 목록을 본다. 로그인 없이는 아무 데이터도 보이지 않는다.
- M2. 마케터로서, 새 리드의 메신저 종류와 ID/전화번호를 보고 해당 메신저로 연락한 뒤 상태를 `contacted`로 바꾼다. 상담이 끝나면 `done`으로 바꾼다.
- M3. 마케터로서, 메신저별·국적별·상태별로 목록을 필터링해 "아직 연락 안 한 위챗 중국 고객"처럼 좁혀 보고 싶다.
- M4. 마케터로서, 리드마다 관리자 메모(예: "8/21 15시 예약 확정")를 남기고 나중에 다시 본다.
- M5. 마케터로서, (필터된) 목록을 CSV로 내려받아 엑셀 보고에 쓴다. 한글이 깨지지 않아야 한다.
- M6. 마케터로서, 휴대폰에서도 대시보드를 쓸 수 있어야 한다(호텔 현장 대응).

## 3. 아키텍처 개요

```
투숙객 브라우저                          마케터 브라우저
voucher.html (GitHub Pages)             admin/index.html (GitHub Pages)
   │  ① POST /rest/v1/leads                │ ② Supabase Auth 로그인 (supabase-js CDN)
   │     (anon key, INSERT만 허용)          │ ③ SELECT / UPDATE /rest/v1/leads
   ▼                                       ▼    (로그인 세션 JWT, 관리자 이메일만 허용)
        Supabase obliv-foreigner (ap-northeast-2)
        └─ public.leads 테이블 + RLS  ← 유일한 보안 경계
```

- 서버 코드 없음. 배포물은 정적 파일뿐이고, 백엔드는 Supabase가 제공하는 그대로(PostgREST + Auth)를 쓴다.
- 구성 요소: ① `public.leads` 테이블 + RLS(마이그레이션 1개) ② `voucher.html` 전송부 수정 ③ `admin/index.html` 신규 1파일.

## 4. 데이터 모델 — `public.leads`

기존 페이로드 계약(BRIEF §"기존 페이로드 계약")의 7개 필드 + 운영 필드. 컬럼명은 PostgREST에 JSON 키가 그대로 매핑되므로 snake_case로 통일한다(클라이언트의 `submittedAt`만 전송부에서 `submitted_at`으로 바꿔 보냄 — §5.3).

| 컬럼 | 타입 | 제약 | 설명 |
|---|---|---|---|
| `id` | `bigint` | PK, `generated always as identity` | 사람이 읽기 쉬운 번호(#123). 조회는 관리자 전용이라 순번 노출 위험 없음 |
| `created_at` | `timestamptz` | `not null default now()` | **서버 수신 시각. 정렬·운영 기준** |
| `name` | `text` | `not null`, 길이 1–100 | 투숙객 이름 |
| `messenger` | `text` | `not null`, `in ('whatsapp','line','wechat','kakaotalk')` | 연락받을 메신저 |
| `contact` | `text` | `not null`, 길이 1–100 | 메신저 ID 또는 전화번호 |
| `nationality` | `text` | `not null`, `in ('KR','US','CN','JP','TW','HK','SG','TH','VN','RU','OTHER')` | 국적 코드 |
| `lang` | `text` | `not null default 'ko'`, `in ('ko','en','zh','ja')` | 제출 당시 페이지 언어 |
| `source` | `text` | `not null default 'voucher'`, 길이 ≤ 40 | 유입 경로(향후 다른 페이지 확장 대비) |
| `submitted_at` | `timestamptz` | nullable | 클라이언트가 보고한 시각(참고용). 신뢰 기준은 `created_at` |
| `status` | `text` | `not null default 'new'`, `in ('new','contacted','done')` | 처리 상태 |
| `admin_memo` | `text` | nullable, 길이 ≤ 2000 | 관리자 메모 |

설계 노트:

- `status`는 enum 타입 대신 **text + CHECK**: 값 추가 시 CHECK만 고치면 되어 유지보수가 쉽다. `messenger`/`nationality`/`lang`도 같은 이유로 text + CHECK — DB의 CHECK가 곧 서버측 입력 검증이다(§6.3).
- 인덱스는 `created_at desc` 1개만. 필터(메신저/국적/상태)는 리드 수천 건 규모에서 인덱스 불필요.
- 중복 제출(같은 연락처 재제출)은 막지 않는다 — 정보 수정 재제출일 수 있어 unique 제약 없이 운영에서 판단.
- `updated_at`·`contacted_at`·soft delete 등은 넣지 않는다(과설계). 삭제는 API에 아예 열지 않고(§6.2) 필요 시 Supabase Studio SQL로만.

### 스키마 SQL 초안 (개발 워커가 `supabase/migrations/0001_leads.sql`로 정리)

```sql
create table public.leads (
  id           bigint generated always as identity primary key,
  created_at   timestamptz not null default now(),
  name         text not null check (char_length(name) between 1 and 100),
  messenger    text not null check (messenger in ('whatsapp','line','wechat','kakaotalk')),
  contact      text not null check (char_length(contact) between 1 and 100),
  nationality  text not null check (nationality in
                 ('KR','US','CN','JP','TW','HK','SG','TH','VN','RU','OTHER')),
  lang         text not null default 'ko' check (lang in ('ko','en','zh','ja')),
  source       text not null default 'voucher' check (char_length(source) <= 40),
  submitted_at timestamptz,
  status       text not null default 'new' check (status in ('new','contacted','done')),
  admin_memo   text check (char_length(admin_memo) <= 2000)
);

create index leads_created_at_idx on public.leads (created_at desc);
```

(RLS 정책 SQL은 §6.2 — 같은 마이그레이션 파일에 포함한다.)

## 5. 수집 API 설계

### 5.1 방식 확정: PostgREST 직접 insert

- **Edge Function(`submit-lead`)**: CORS를 origin 단위로 직접 제어하고 서버측 검증·요율제한 코드를 넣을 수 있으나, Deno 코드 배포·수정이 코디네이터 MCP를 거쳐야 하는 유지보수 대상이 하나 늘어난다.
- **PostgREST 직접 insert**: 배포·유지보수할 코드가 0이고, 입력 검증은 DB CHECK 제약이 대신하며, 익명 권한은 RLS로 INSERT만으로 조인다.
- **확정: PostgREST 직접 insert.** 이 프로젝트의 실질 보안 경계는 어차피 CORS가 아니라 RLS이고(§6.1), "마케터가 유지보수 가능한 최소 구성" 원칙에 부합한다. 스팸이 실제로 발생하면 그때 Edge Function으로 승격한다(§6.4 대응 시나리오).

### 5.2 CORS 정책

- Supabase REST API(PostgREST)는 기본으로 모든 origin에 `Access-Control-Allow-Origin: *`를 응답하므로 **`https://burwoodjoy.github.io`에서의 호출은 추가 설정 없이 허용된다.** preflight(OPTIONS)도 Supabase 게이트웨이가 처리한다.
- REST API의 CORS를 특정 origin으로 좁히는 설정은 제공되지 않지만, CORS는 브라우저 예의일 뿐 보안 경계가 아니다(curl 등 비브라우저 클라이언트는 CORS를 무시한다). 익명이 할 수 있는 일은 origin과 무관하게 RLS가 "leads INSERT 1가지"로 제한한다.
- (참고) origin 허용목록이 꼭 필요해지면 그것이 Edge Function 승격 사유다.

### 5.3 요청 스펙 (voucher.html 전송부가 보낼 것)

```
POST https://dqnjbheejjtoitrbzxmp.supabase.co/rest/v1/leads
Content-Type: application/json
apikey: <SUPABASE_ANON_KEY>            ← BRIEF CONFIG 값
Authorization: Bearer <SUPABASE_ANON_KEY>
Prefer: return=minimal
```

```json
{
  "name":         "홍길동",
  "messenger":    "whatsapp",
  "contact":      "+82 10-1234-5678",
  "nationality":  "KR",
  "lang":         "ko",
  "source":       "voucher",
  "submitted_at": "2026-08-19T12:34:56.000Z"
}
```

voucher.html 전송부 수정 범위(코드는 개발 단계에서):

1. `LEAD_ENDPOINT`를 위 REST URL로 설정하고, 상수 `SUPABASE_ANON_KEY`를 추가한다(스크립트 상단 주석 블록 `voucher.html:1154–1175`도 실제 연동 상태에 맞게 갱신).
2. `fetch` 호출(`voucher.html:1259`)에 `apikey`/`Authorization`/`Prefer: return=minimal` 헤더를 추가한다.
3. payload의 `submittedAt` 키만 `submitted_at`으로 바꿔 보낸다(나머지 키는 컬럼명과 이미 일치).
4. 성공 판정은 기존 `res.ok` 그대로(201도 ok), 실패 시 기존 `formSendError` 흐름 그대로. **폼 UI·검증·i18n·success 화면은 무변경.**

### 5.4 응답 스펙

| 상태 | 의미 | 클라이언트 동작 |
|---|---|---|
| `201 Created` (본문 없음, `return=minimal`) | 저장 성공 | 성공 화면 표시 (기존 `showSuccess()`) |
| `400/422` | CHECK 제약 위반(비정상 값)·JSON 오류 | `formSendError` 표시, 버튼 재활성화 (기존 catch 흐름) |
| `401` | anon key 누락/오타 | 〃 (배포 설정 오류 — E2E에서 걸러냄) |
| `403` | RLS 위반(INSERT 외 시도 등) | 〃 |

`return=minimal`은 필수다: anon에게 SELECT 정책이 없으므로 `return=representation`을 쓰면 삽입 후 행 반환 단계에서 실패한다(그리고 반환할 이유도 없다).

### 5.5 관리자 조회/수정 API (대시보드가 사용)

`admin/index.html`은 supabase-js(CDN)로 로그인 세션 JWT를 실어 같은 REST를 호출한다. 개념 스펙:

- 목록: `GET /rest/v1/leads?select=*&order=created_at.desc&limit=1000` — 리드가 1,000건을 넘기 전까지는 단일 요청으로 충분(넘으면 그때 페이지네이션 추가).
- 상태 변경: `PATCH /rest/v1/leads?id=eq.<id>` body `{"status":"contacted"}`
- 메모 저장: `PATCH /rest/v1/leads?id=eq.<id>` body `{"admin_memo":"..."}`
- 필터는 클라이언트 메모리에서 처리(서버 쿼리 파라미터 불필요 — 데이터가 작다).

## 6. 보안 설계

### 6.1 원칙

- 공개되는 것은 **anon(publishable) key뿐**이며, 이 키로 가능한 일은 RLS가 정의한다. 즉 "키가 노출되어도 안전한 만큼만 권한을 연다"가 전부다.
- `service_role` 등 비밀키는 레포·문서·대시보드 코드 어디에도 절대 넣지 않는다(BRIEF 제약 3 재확인).

### 6.2 RLS 정책 (마이그레이션에 포함할 SQL 초안)

```sql
alter table public.leads enable row level security;

-- 익명(투숙객 폼): INSERT만. SELECT/UPDATE/DELETE 정책 없음 = 전부 거부.
create policy "anon_insert_leads"
  on public.leads for insert
  to anon
  with check (true);

-- 관리자(마케터): 조회
create policy "admin_select_leads"
  on public.leads for select
  to authenticated
  using (lower(auth.jwt() ->> 'email') = 'yh.jung@medibuilder.com');

-- 관리자(마케터): 수정 (대시보드는 status / admin_memo만 수정함)
create policy "admin_update_leads"
  on public.leads for update
  to authenticated
  using (lower(auth.jwt() ->> 'email') = 'yh.jung@medibuilder.com')
  with check (lower(auth.jwt() ->> 'email') = 'yh.jung@medibuilder.com');
```

- **DELETE 정책은 만들지 않는다** — anon도 관리자도 API로는 삭제 불가. 삭제가 필요하면 프로젝트 소유자가 Supabase Studio SQL로 직접.
- `authenticated`라도 이메일이 다르면 아무 행도 보이지 않는다. 관리자를 추가하려면 위 두 정책의 `=`를 `in ('yh.jung@medibuilder.com', '추가이메일')`로 바꾸는 마이그레이션 1개면 된다(관리자 테이블 등은 현 단계 과설계).
- 전제: Supabase Auth의 이메일 확인(Confirm email)이 켜져 있어야 타인이 해당 이메일로 위장 가입할 수 없다(기본값 ON — 배포 체크리스트에서 확인, §8·§10).

### 6.3 입력 검증

서버측 검증 = §4의 CHECK 제약. 허용 enum 밖의 `messenger`/`nationality`/`lang`/`status`, 길이 초과, 누락 필드는 DB가 400/422로 거절한다. 클라이언트 검증(기존 voucher.html)은 UX용이고, 신뢰 경계는 DB다.

### 6.4 스팸·남용 대비 (최소장치)

| 장치 | 내용 |
|---|---|
| 길이·enum CHECK | 쓰레기 대량 텍스트·비정상 값 저장 차단(행 크기 상한 고정) |
| INSERT-only + `return=minimal` | 폼 엔드포인트로는 어떤 데이터도 읽어갈 수 없음 |
| 중복 클릭 방지 | 기존 `btn.disabled`(voucher.html) 유지 |
| 대시보드 status 필터 | 스팸 행은 `done` 처리 또는 Studio SQL로 일괄 삭제해 운영 격리 |

한계와 대응 시나리오: PostgREST 직접 insert에는 IP당 요율제한이 없어, 악의적 스크립트가 유효한 형식의 행을 대량 삽입하는 것 자체는 막지 못한다(저가치 타깃·투숙객 전용 안내 페이지라 위험 수용). **실제 스팸 발생 시** 승격 경로: ① Studio SQL로 스팸 삭제 → ② Edge Function `submit-lead`로 전환(origin 허용목록 + 간단한 요율제한 + honeypot 필드)하고 voucher.html의 URL만 교체. 이 시나리오가 있으므로 지금 미리 만들지 않는다.

### 6.5 개인정보 취급

- 저장 항목은 이름·연락처·국적·언어뿐(폼 하단 고지 "예약 상담 목적" 기존 문구와 일치). 결제·여권 등 민감정보 없음.
- 조회 가능자는 관리자 1인. CSV 반출 후 파일 관리는 마케터 책임(대시보드에 별도 고지 불필요 — 사내 사용자 1인).

## 7. 관리자 대시보드 UX 스펙 — `admin/index.html`

단일 정적 HTML + supabase-js v2 CDN. 언어는 한국어 고정(사용자가 마케터 1인). 접속 URL: `https://burwoodjoy.github.io/admin/`.

### 7.1 디자인 언어 — 바우처 페이지와 동일한 골드/블랙 톤

voucher.html의 토큰을 그대로 재사용한다 (`voucher.html:11–21`):

- 색: `--black #0c0c0e`(배경) / `--charcoal-2 #1f1e22`(카드) / `--gold #c9a75e`·`--gold-light #e8d9b0`·`--gold-deep #a4813f`(강조·주요 버튼 그라데이션) / `--ivory #f6f2ea`(본문) / `--muted #a9a39a`(보조) / `--line rgba(201,167,94,0.28)`(테두리)
- 폰트: Noto Sans KR(본문), Cormorant Garamond(로고/타이틀 악센트) — 동일한 Google Fonts 로드
- 형태: 카드 radius 18px·입력 radius 12px·pill 버튼(999px)·골드 그라데이션 주버튼 등 기존 `.lead-card`/`.submit-btn` 문법을 따른다

### 7.2 화면 구성

**A. 로그인 화면** (비로그인 시 유일하게 보이는 화면)

- 중앙 카드: "OBLIV LEADS" 타이틀, 이메일·비밀번호 입력, [로그인] 골드 버튼
- 실패 시 카드 안에 인라인 오류("이메일 또는 비밀번호가 올바르지 않습니다"), 로딩 중 버튼 비활성
- 회원가입·비밀번호 재설정 UI 없음(계정은 §10의 수동 작업으로 생성). 세션은 supabase-js 기본(localStorage)으로 유지 — 재방문 시 자동 로그인 복원

**B. 리드 목록 화면** (로그인 후)

1. 헤더: 타이틀 + 로그인 이메일 + [로그아웃]
2. 요약 칩: 전체 n · new n · contacted n · done n (현재 로드된 데이터 기준, 클릭 시 해당 상태 필터 적용)
3. 필터 바 (모바일에서 상단 고정 권장):
   - 메신저: 전체 / 왓츠앱 / 라인 / 위챗 / 카카오톡
   - 국적: 전체 / KR·US·CN·JP·TW·HK·SG·TH·VN·RU·OTHER
   - 상태: 전체 / new / contacted / done
   - 세 필터는 AND 결합, 적용은 즉시(클라이언트 필터링), [초기화] 제공
4. 리드 카드 리스트 — **`created_at` 최신순 고정**, 카드당:
   - 1행: `#id` · 이름(강조) · 상태 배지(new=골드 채움 / contacted=골드 외곽선 / done=muted)
   - 2행: 메신저 아이콘+이름(voucher.html의 SVG 재사용 가능) · 연락처(탭하면 클립보드 복사 + "복사됨" 토스트) · 국적 국기+코드 · 언어
   - 3행: 접수 시각 — `created_at`을 **KST로 표기**(예: `2026-08-19 21:34`)
   - 4행: 상태 변경 `<select>`(new/contacted/done) — 변경 즉시 PATCH, 실패 시 원복+오류 토스트
   - 5행: 메모 textarea + [메모 저장] — 저장 성공 시 "저장됨" 표시, 실패 시 오류 토스트(입력값 유지)
5. 툴바: [CSV 내보내기] — **현재 필터가 적용된** 행을 클라이언트에서 생성해 다운로드
   - 컬럼: `id, created_at(KST), name, messenger, contact, nationality, lang, status, admin_memo, submitted_at, source`
   - **UTF-8 BOM 포함**(엑셀 한글 깨짐 방지), 파일명 `leads_YYYYMMDD.csv`
6. 상태 화면: 로딩("불러오는 중…"), 빈 목록("아직 접수된 문의가 없습니다"), 로드 실패(오류 문구 + [다시 시도])
7. 새로고침: 수동 [새로고침] 버튼 1개(실시간 구독은 과설계 — 필요해지면 supabase-js Realtime 추가 여지만 남김)

**C. 모바일 대응**

- 바우처와 같은 모바일 우선: 카드 1열, 본문 컨테이너 max-width ~720px(데스크톱에서 중앙 정렬), 터치 타깃 44px 이상, 필터는 가로 스크롤 칩 또는 셀렉트
- 가로 스크롤 없는 레이아웃(표 대신 카드 리스트를 쓰는 이유)

### 7.3 선택(있으면 좋음, 없어도 수용)

- 이름/연락처 텍스트 검색(클라이언트 필터라 저비용)
- 왓츠앱 연락처를 `https://wa.me/<숫자>` 링크로 연결

## 8. 개발 체크리스트 · 수용 기준

개발 워커 산출물(BRIEF 규약): `supabase/migrations/0001_leads.sql` / `admin/index.html` / `voucher.html` 전송부 수정 / `docs/lead-app/DEV-NOTES.md`. Edge Function은 **만들지 않는다**(§5.1). 로컬 커밋만, 푸시 금지.

체크리스트:

- [ ] `0001_leads.sql`: §4 테이블 + 인덱스 + §6.2 RLS를 한 파일로. 문법을 로컬에서 자체 검토(적용은 코디네이터)
- [ ] `voucher.html`: §5.3의 4개 항목만 수정(diff가 스크립트 전송부와 주석 블록에 국한되는지 확인). anon key는 BRIEF CONFIG 값 사용 — 코디네이터 기입 전이면 `orca orchestration ask`로 요청
- [ ] `admin/index.html`: §7 전체(로그인/목록/필터/상태변경/메모/CSV/상태화면/모바일). 외부 의존성은 Google Fonts + supabase-js CDN만
- [ ] `docs/lead-app/DEV-NOTES.md`: 구현 결정·검증 방법·미해결 사항 기록
- [ ] 로컬 검증: `python3 -m http.server`로 두 페이지 렌더·동작 확인(DB 연동 전이면 오류 경로 확인까지)

수용 기준(Acceptance Criteria):

- AC-1. 유효한 폼 제출 시 `leads`에 행 1개가 생기고, 페이지에는 기존 성공 화면이 뜬다. `created_at`이 서버 시각으로 채워진다.
- AC-2. 전송 실패(오프라인·4xx/5xx) 시 기존 `formSendError` 문구가 뜨고 버튼이 다시 활성화되며, 재제출이 가능하다.
- AC-3. 허용 enum 밖 값(예: `messenger:"telegram"`)을 강제로 POST하면 4xx로 거절되고 행이 생기지 않는다.
- AC-4. anon key만으로 `GET /rest/v1/leads`를 호출하면 데이터가 반환되지 않는다(빈 배열 또는 오류).
- AC-5. `yh.jung@medibuilder.com`으로 로그인하면 전체 리드가 최신순으로 보인다. 다른 계정으로 로그인하면 0건이다.
- AC-6. 대시보드에서 상태 변경·메모 저장이 DB에 반영되고 새로고침 후에도 유지된다.
- AC-7. 세 필터(메신저/국적/상태)가 AND로 동작하고, CSV는 필터된 행만 포함하며 엑셀에서 한글이 정상 표시된다.
- AC-8. 폭 375px(아이폰급)에서 두 페이지 모두 가로 스크롤 없이 조작 가능하다.
- AC-9. voucher.html의 폼 UI·검증·i18n 관련 diff가 없다(전송부·주석만 변경).

## 9. 배포·검증 체크리스트 (배포 워커)

순서대로:

- [ ] D-1. 코디네이터에게 ask: `0001_leads.sql` 마이그레이션 적용(MCP `apply_migration`) + anon key가 BRIEF CONFIG에 기입됐는지 확인
- [ ] D-2. 코디네이터에게 ask: Supabase Auth 설정 확인 — 이메일/비밀번호 provider 활성, **Confirm email ON**
- [ ] D-3. 관리자 계정 준비(§10 수동 작업)가 끝났는지 사용자 확인 후 진행
- [ ] D-4. `git push` (main = 배포). GitHub Pages 반영 대기 후 실제 URL로 E2E:

| # | 시나리오 | 기대 결과 |
|---|---|---|
| E2E-1 | `https://burwoodjoy.github.io/voucher.html`에서 4개 필드 입력 후 제출(언어 1개는 en으로 반복) | 성공 화면 표시. 코디네이터 SQL 조회로 행 확인(`lang` 값 포함) |
| E2E-2 | 필수값 누락 제출 | 기존 클라이언트 검증 오류(네트워크 요청 없음) |
| E2E-3 | curl로 enum 밖 값 POST | 4xx, 행 미생성 (AC-3) |
| E2E-4 | curl로 anon key SELECT | 데이터 없음 (AC-4) |
| E2E-5 | `admin/`에서 잘못된 비밀번호 → 올바른 로그인 | 오류 표시 → 목록 최신순 표시, E2E-1의 리드 보임 |
| E2E-6 | 상태 new→contacted, 메모 저장 → 새로고침 | 값 유지 (AC-6) |
| E2E-7 | 필터 조합 + CSV 다운로드 → 엑셀 열기 | 필터 반영·한글 정상 (AC-7) |
| E2E-8 | 휴대폰(또는 375px 에뮬)에서 제출→관리 전 과정 | 레이아웃·터치 정상 (AC-8) |
| E2E-9 | 로그아웃 → 대시보드 재접속 | 로그인 화면만 보임, 데이터 비노출 |

- [ ] D-5. 결과를 `docs/lead-app/DEPLOY-REPORT.md`로 기록(각 E2E pass/fail, 잔여 이슈)
- [ ] D-6. 실패 항목이 있으면 개발 워커/코디네이터에 반환하고 재검증 전까지 "실 손님 안내 가능" 선언 금지

## 10. 남는 수동 작업 (사용자/코디네이터)

| 작업 | 담당 | 내용 |
|---|---|---|
| 관리자 계정 생성 | **사용자 본인** | Supabase Studio → Authentication → Users → Add user(또는 초대 메일)로 `yh.jung@medibuilder.com` 계정과 비밀번호를 직접 생성. 워커·코디네이터는 자격증명을 다루지 않음(BRIEF 규약) |
| anon key 기입 | 코디네이터 | BRIEF CONFIG의 `SUPABASE_ANON_KEY` 채우기 |
| 마이그레이션 적용·SQL 검증 조회 | 코디네이터 | MCP로 수행(워커는 Supabase 접속 불가) |
| Auth 설정 확인 | 코디네이터(확인) + 사용자(변경) | Confirm email ON 유지. 관리자 계정 생성 후 원하면 공개 회원가입 비활성화(Studio) — 비활성화해도 RLS상 타 계정은 어차피 0건이므로 선택 사항 |
| 실 운영 판단 | 사용자 | E2E 전체 통과 확인 후 손님 안내 시작. 스팸 발생 시 §6.4 시나리오로 승격 결정 |

## 11. 범위 외 (Non-goals — 과설계 방지 목록)

다음은 의도적으로 만들지 않는다. 필요가 실측되면 그때 추가한다.

- Edge Function·서버 코드·요율제한·honeypot (승격 경로만 §6.4에 예약)
- 신규 알림(이메일/슬랙 웹훅), 실시간 구독, 통계 차트
- 페이지네이션(1,000건 도달 전까지), 관리자 다중화용 별도 테이블, 역할(role) 체계
- 리드 삭제 UI, 감사 로그, `updated_at` 트리거
- 대시보드 다국어화, 다크/라이트 테마 전환(골드/블랙 단일 테마)
- voucher.html 폼 UI·검증·문구 변경

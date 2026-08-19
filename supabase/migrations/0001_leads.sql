-- ============================================================================
-- 0001_leads.sql — 리드 수집 테이블 + RLS 정책
--
-- 설계 근거: docs/lead-app/PLAN.md §4(데이터 모델) · §6.2(RLS)
-- 대상 프로젝트: Supabase obliv-foreigner (ref: dqnjbheejjtoitrbzxmp, ap-northeast-2)
-- 적용 방법: 워커는 Supabase 접근 권한이 없으므로 코디네이터가 MCP
--            apply_migration 으로 이 파일 전체를 실행한다 (docs/lead-app/DEV-NOTES.md 참고).
-- ============================================================================

-- 리드 테이블: voucher.html 폼 페이로드 7개 필드 + 운영 필드(status/admin_memo).
-- 값 검증은 text + CHECK 제약으로 수행 — DB의 CHECK가 곧 서버측 입력 검증이다(PLAN §6.3).
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

comment on table public.leads is
  'burwoodjoy.github.io/voucher.html 리드 폼 제출 데이터. created_at(서버 수신 시각)이 정렬·운영 기준이며 submitted_at은 클라이언트 보고 시각(참고용).';

-- 정렬(최신순) 전용 인덱스 1개. 필터 컬럼 인덱스는 수천 건 규모에서 불필요(PLAN §4).
create index leads_created_at_idx on public.leads (created_at desc);

-- ============================================================================
-- RLS — 이 테이블의 유일한 보안 경계 (PLAN §6.2)
--   anon          : INSERT만 허용 (SELECT/UPDATE/DELETE 정책 없음 = 전부 거부)
--   authenticated : 허용된 관리자 이메일만 SELECT/UPDATE
--   DELETE        : 어떤 역할에도 정책 없음 — API로는 삭제 불가.
--                   삭제가 필요하면 프로젝트 소유자가 Supabase Studio SQL로만 수행.
-- 관리자 추가 시: 아래 두 정책의 `=` 비교를
--   in ('yh.jung@medibuilder.com', '추가이메일') 로 바꾸는 마이그레이션 1개면 된다.
-- ============================================================================

alter table public.leads enable row level security;

-- 익명(투숙객 폼): INSERT만.
create policy "anon_insert_leads"
  on public.leads for insert
  to anon
  with check (true);

-- 관리자(마케터): 조회.
create policy "admin_select_leads"
  on public.leads for select
  to authenticated
  using (lower(auth.jwt() ->> 'email') = 'yh.jung@medibuilder.com');

-- 관리자(마케터): 수정 (대시보드는 status / admin_memo만 수정한다).
create policy "admin_update_leads"
  on public.leads for update
  to authenticated
  using (lower(auth.jwt() ->> 'email') = 'yh.jung@medibuilder.com')
  with check (lower(auth.jwt() ->> 'email') = 'yh.jung@medibuilder.com');

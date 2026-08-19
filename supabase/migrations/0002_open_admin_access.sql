-- ============================================================================
-- 0002_open_admin_access.sql — 관리자 로그인 절차 제거 (2026-08-19 사용자 결정)
--
-- 배경: "이메일/비번 적는 절차는 없애줘. 쉽게 접근 가능하게" — 대시보드가
--       로그인 없이 공개 anon 키만으로 리드를 조회·수정하도록 RLS를 연다.
-- 결과: 대시보드 URL(공개 레포에 노출)을 아는 누구나 리드 조회·수정 가능.
--       사용자가 이 트레이드오프를 인지하고 수용함.
-- 유지: 익명 INSERT 정책(anon_insert_leads), DELETE 정책 없음(= API 삭제 불가
--       — 실수·장난으로 인한 데이터 유실 방지. 삭제는 Supabase Studio SQL로만).
-- 되돌리기: 이 파일의 정책을 drop하고 0001의 admin_* 정책을 재생성하면 된다.
-- ============================================================================

drop policy "admin_select_leads" on public.leads;
drop policy "admin_update_leads" on public.leads;

-- 누구나(익명 포함) 조회
create policy "public_select_leads"
  on public.leads for select
  to anon, authenticated
  using (true);

-- 누구나(익명 포함) 수정 — 대시보드는 status / admin_memo만 수정한다
create policy "public_update_leads"
  on public.leads for update
  to anon, authenticated
  using (true)
  with check (true);

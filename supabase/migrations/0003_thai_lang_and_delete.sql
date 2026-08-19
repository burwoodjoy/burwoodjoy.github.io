-- ============================================================================
-- 0003_thai_lang_and_delete.sql — 태국어 지원 + 대시보드 삭제 버튼 (2026-08-19 사용자 결정)
--
-- 1) 바우처 페이지에 태국어(th)가 추가됨 → lang CHECK 제약에 'th' 허용.
-- 2) 대시보드에 리드 삭제 버튼 추가 → DELETE 정책 개방(로그인 없음 정책과 일관).
--    실수 방지는 UI의 2단계 확인(삭제 → 정말 삭제)으로 처리한다.
-- ============================================================================

alter table public.leads drop constraint leads_lang_check;
alter table public.leads add constraint leads_lang_check
  check (lang in ('ko','en','zh','ja','th'));

create policy "public_delete_leads"
  on public.leads for delete
  to anon, authenticated
  using (true);

-- ============================================================================
-- 0004_slack_notify_new_lead.sql — 새 리드 접수 시 Slack 알림 (2026-08-19)
--
-- 새 리드가 leads 테이블에 INSERT 되면 Slack 봇 "호텔QR 상담신청"이
-- 채널(C0BQS9XT9DM)에 알림 메시지를 보낸다.
--
-- 구조: AFTER INSERT 트리거 → pg_net 비동기 HTTP POST → Slack chat.postMessage
--   - 봇 토큰은 Supabase Vault에 'slack_bot_token' 이름으로 암호화 저장
--     (이 레포에는 절대 포함하지 않음. 교체 시:
--      select vault.update_secret((select id from vault.secrets where name='slack_bot_token'), '새토큰');)
--   - pg_net은 비동기 큐라서 폼 제출 속도에 영향 없음
--   - 알림이 실패해도 리드 저장(INSERT)은 절대 막지 않음 (예외 무시)
--   - 발송 결과 확인: select * from net._http_response order by id desc;
--   - 주의: pg_net은 Content-Type이 정확히 'application/json'이어야 함
--     ('; charset=utf-8' 붙이면 P0001 에러로 거부됨 — 실제로 겪은 함정)
-- ============================================================================

create extension if not exists pg_net;

create or replace function public.notify_slack_new_lead()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  slack_token text;
  messenger_label text;
  msg_text text;
begin
  select decrypted_secret into slack_token
  from vault.decrypted_secrets
  where name = 'slack_bot_token';

  if slack_token is null then
    return new;  -- 토큰 미설정이어도 리드 저장은 정상 진행
  end if;

  messenger_label := case new.messenger
    when 'whatsapp'  then '왓츠앱'
    when 'line'      then '라인'
    when 'wechat'    then '위챗'
    when 'kakaotalk' then '카카오톡'
    else new.messenger
  end;

  msg_text :=
       '🔔 *새 예약 문의가 접수되었습니다* (#' || new.id || ')' || E'\n'
    || '• 이름: ' || new.name || E'\n'
    || '• 메신저: ' || messenger_label || ' — `' || new.contact || '`' || E'\n'
    || '• 국적 / 언어: ' || new.nationality || ' / ' || upper(new.lang) || E'\n'
    || '• 접수: ' || to_char(new.created_at at time zone 'Asia/Seoul', 'YYYY-MM-DD HH24:MI') || ' KST' || E'\n'
    || '<https://burwoodjoy.github.io/admin-98b2611118b00ac1/|→ 대시보드에서 확인>';

  perform net.http_post(
    url := 'https://slack.com/api/chat.postMessage',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || slack_token
    ),
    body := jsonb_build_object(
      'channel', 'C0BQS9XT9DM',
      'text', msg_text,
      'unfurl_links', false
    ),
    timeout_milliseconds := 5000
  );

  return new;
exception when others then
  return new;  -- 어떤 오류여도 INSERT는 성공시킨다
end;
$$;

-- PostgREST RPC로 노출되지 않도록 실행 권한 회수(트리거 실행은 소유자 권한이라 무관)
revoke execute on function public.notify_slack_new_lead() from public, anon, authenticated;

drop trigger if exists trg_notify_slack_new_lead on public.leads;
create trigger trg_notify_slack_new_lead
  after insert on public.leads
  for each row
  execute function public.notify_slack_new_lead();

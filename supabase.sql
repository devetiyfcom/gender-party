-- Gender party: sesverme + qonaq defteri (sayta uygun versiya)
drop function if exists public.cast_vote(text,text,text);
drop function if exists public.get_results(text,text);
drop table if exists public.votes;

create table public.votes (
  id bigint generated always as identity primary key,
  event text not null,
  device text not null,
  name text not null,
  choice text not null check (choice in ('boy','girl')),
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique (event, device)
);
alter table public.votes enable row level security;
revoke all on public.votes from anon, authenticated;

create table if not exists public.messages (
  id bigint generated always as identity primary key,
  event text not null,
  device text not null,
  name text not null,
  body text not null,
  created_at timestamptz default now()
);
alter table public.messages enable row level security;
revoke all on public.messages from anon, authenticated;

create or replace function public.cast_vote(p_event text, p_device text, p_choice text, p_name text)
returns text language plpgsql security definer set search_path = public as $$
declare v_close timestamptz;
begin
  select closes_at into v_close from events where event = p_event;
  if v_close is null then raise exception 'event not found'; end if;
  if now() >= v_close then raise exception 'voting closed'; end if;
  insert into votes(event, device, name, choice)
  values (p_event, left(p_device,100), left(trim(p_name),40), p_choice)
  on conflict (event, device) do update
    set choice = excluded.choice, name = excluded.name, updated_at = now();
  return 'ok';
end $$;

create or replace function public.send_message(p_event text, p_device text, p_name text, p_text text)
returns text language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from events where event = p_event) then raise exception 'event not found'; end if;
  if (select count(*) from messages where event = p_event and device = p_device) >= 10 then
    raise exception 'too many messages';
  end if;
  insert into messages(event, device, name, body)
  values (p_event, left(p_device,100), left(trim(p_name),40), left(trim(p_text),500));
  return 'ok';
end $$;

create or replace function public.get_results(p_event text, p_pin text)
returns table(choice text, say bigint) language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from events where event = p_event and host_pin = p_pin) then raise exception 'wrong pin'; end if;
  return query select v.choice, count(*) from votes v where v.event = p_event group by v.choice;
end $$;

create or replace function public.get_votes(p_event text, p_pin text)
returns table(name text, choice text, updated_at timestamptz) language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from events where event = p_event and host_pin = p_pin) then raise exception 'wrong pin'; end if;
  return query select v.name, v.choice, v.updated_at from votes v where v.event = p_event order by v.updated_at desc;
end $$;

create or replace function public.get_messages(p_event text, p_pin text)
returns table(name text, body text, created_at timestamptz) language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from events where event = p_event and host_pin = p_pin) then raise exception 'wrong pin'; end if;
  return query select m.name, m.body, m.created_at from messages m where m.event = p_event order by m.created_at desc;
end $$;

grant execute on function public.cast_vote(text,text,text,text) to anon;
grant execute on function public.send_message(text,text,text,text) to anon;
grant execute on function public.get_results(text,text) to anon;
grant execute on function public.get_votes(text,text) to anon;
grant execute on function public.get_messages(text,text) to anon;

insert into events(event, host_pin, closes_at)
values ('gender-party', '1234', '2026-11-29 18:00+04')
on conflict (event) do update set host_pin = excluded.host_pin, closes_at = excluded.closes_at;

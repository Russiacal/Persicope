with 
-- summarize users by org
  org_users as (
	select
	  organization_id as org_id,
	  count(id) as user_count
	from truelink.public.users
	group by 1
	order by 1 asc
),
-- find first revenue per org
org_first_rev as (
  select
      omt.org_id as org_id,
      to_date((omt.year||'-'||omt.month||'-01'),'YYYY-MM-DD') as month_year
    from analytics__org_monthly_totals omt
      where period_idx =0
),
-- figure out when card first got funded
card_funded as (
  select
        card_reference, 
        date(min(transaction_at))
      from nightly_posts
      where transaction_code in ('21','dd')
      group by 1
),
-- summarize card counts at org level, identify how many open, funded and how many vcc
  vcc_cards as (
  select 
    o.id as org_id,
    count (distinct a.id) as a_count,
    
    count (c.id) as c_count,
    count (case when c.status NOT IN ('ISSUED_INACTIVE') then c.id end) as c_opened,
    count (cf.card_reference) as c_funded,
    
    count(distinct case when p.first_name = 'Valued' and p.last_name = 'Customer' and a.bulk_card_ordered = 1 then a.id end) as a_vcc,
    
    count(case when [value_customer_card] then c.id end) as c_vcc,
    count(case when [value_customer_card] and c.status NOT IN ('ISSUED_INACTIVE') then c.id end) as c_vcc_opened 
    
  from cards c
    join accounts a on a.id = c.account_id
    join organizations o on o.id = a.organization_id
    join people p on p.id = c.person_id
    left join card_funded cf on cf.card_reference = c.card_reference
  group by 1
),

-- summarize users, cards, and accounts at org level
  org_level_detail as (
    select
      o.id as org_id,
      coalesce(o.parent_org_id, o.id) as parent_id,
      o.org_type as org_type,
      o.customer_type as customer_type,
      coalesce(ofr.month_year, date_trunc('month', o.created_at::date)::date) as create_cohort,
     
      vcc.a_count as a_count,
      (vcc.a_count - vcc.a_vcc) as a_ex_vcc,

      vcc.c_count as c_count,
      (vcc.c_count - vcc.c_vcc) as c_ex_vcc,
      vcc.c_opened as c_opened,
      (vcc.c_opened - vcc.c_vcc_opened) as c_opened_ex_vcc,
      vcc.c_funded as c_funded,
      (case when vcc.c_vcc > 0 and c_ex_vcc = 0 then 1 else 0 end ) as vcc_only,
    
      sum(ou.user_count) as ads

    from organizations o
        left join org_first_rev ofr
          on o.id = ofr.org_id
        left join org_users ou
          on ou.org_id=o.id
        join vcc_cards vcc
          on vcc.org_id = o.id
      where [validated_customer_orgs]
      group by 1,2,3,4,5,6,7,8,9,10,11,12,13
      order by 5 desc
  )

select
  count(org_id) as org_count,
  sum(ads) as ad_count,
  org_type,
  create_cohort,

  sum(a_ex_vcc)::numeric as accounts,
  sum(c_ex_vcc)::numeric as cards, 
  sum(c_opened_ex_vcc)::numeric as cards_open,
  sum(c_funded)::numeric as cards_open_funded,

  round((accounts/ org_count),2) as accounts_per_org,
  round((cards/ org_count),2) as cards_per_org, 
  round((cards_open/ org_count),2) as cards_open_per_org,
  round((cards_open_funded/ org_count),2) as cards_open_funded_per_org,

  round((accounts/ ad_count),2) as accounts_per_ad,
  round((cards/ ad_count),2) as cards_per_ad, 
  round((cards_open/ ad_count),2) as cards_open_per_ad,
  round((cards_open_funded/ ad_count),2) as cards_open_funded_per_ad

from 
  org_level_detail
where vcc_only <> 1
group by 3,4
order by 3,4
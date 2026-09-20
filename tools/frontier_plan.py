"""Bounded executable campaign plans. No model-authored code or arbitrary assets."""
import math
WEAPONS=('rifle','smg','rocket')
DEFENSE=('entrench','crossfire','fallback')
CONSTRUCTION=('balanced','north_first','south_first','dig_first','sandbag_first')

def sector_plan(v, allowed=None):
    if not isinstance(v,dict) or set(v)!={'template','defenders','defense','construction','armor','reason'}:raise ValueError('invalid_battle_plan')
    if not isinstance(v['template'],str) or (allowed is not None and v['template'] not in allowed):raise ValueError('invalid_plan_template')
    rows=v['defenders']
    if not isinstance(rows,list) or not 2<=len(rows)<=3:raise ValueError('invalid_defenders')
    for row in rows:
        if not isinstance(row,dict) or set(row)!={'weapon','station'} or row['weapon'] not in WEAPONS or type(row['station']) is not int or row['station'] not in range(3):raise ValueError('invalid_defender_station')
    if len({r['station'] for r in rows})!=len(rows):raise ValueError('duplicate_defender_station')
    if v['defense'] not in DEFENSE or v['construction'] not in CONSTRUCTION:raise ValueError('invalid_plan_policy')
    if not isinstance(v['armor'],dict) or set(v['armor'])!={'green','red'}:raise ValueError('invalid_armor_plan')
    for tank in v['armor'].values():
        if not isinstance(tank,dict) or set(tank)!={'enabled','delay','role'} or type(tank['enabled']) is not bool or type(tank['delay']) not in (int,float) or not math.isfinite(tank['delay']) or not 0<=tank['delay']<=20 or tank['role'] not in ('support','push'):raise ValueError('invalid_armor_plan')
    if v['armor']['green']['enabled'] and not any(r['weapon']=='rocket' for r in rows):raise ValueError('defenders_need_anti_armor')
    if not isinstance(v['reason'],str) or not 1<=len(v['reason'])<=160:raise ValueError('invalid_plan_reason')
    return v

def campaign_plan(value,allowed):
    rows=value.get('sectors') if isinstance(value,dict) else None
    if not isinstance(rows,list) or len(rows)!=3:raise ValueError('invalid_campaign_plan')
    plans=[sector_plan(v,allowed) for v in rows]
    if len({p['template'] for p in plans})!=3:raise ValueError('repeated_campaign_layout')
    if not all(plans[0]['armor'][team]['enabled'] for team in ('green','red')):raise ValueError('opening_requires_both_tanks')
    return {'sectors':plans,'strategy':str(value.get('strategy',''))[:240]}

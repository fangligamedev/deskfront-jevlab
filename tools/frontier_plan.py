"""Bounded executable campaign plans. No model-authored code or arbitrary assets."""
import math
import json
from pathlib import Path
COMPONENTS=json.loads((Path(__file__).resolve().parents[1]/"data/frontier_components.json").read_text())
RULES=json.loads((Path(__file__).resolve().parents[1]/"data/eastfront.json").read_text())
LENGTH=RULES["width"]
LIMITS=RULES["layout_limits"]
THEMES=("meadow","dust","ruins","trench","supply","ridge","village","industrial","forest")
WEAPONS=('rifle','smg','rocket')
DEFENSE=('entrench','crossfire','fallback')
CONSTRUCTION=('balanced','north_first','south_first','dig_first','sandbag_first')

def sector_plan(v, allowed=None):
    if not isinstance(v,dict) or set(v)-{'layout'}!={'template','defenders','defense','construction','armor','reason'}:raise ValueError('invalid_battle_plan')
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
    if 'layout' in v:validate_layout(v['layout'])
    return v

def campaign_plan(value,allowed):
    rows=value.get('sectors') if isinstance(value,dict) else None
    if not isinstance(rows,list) or len(rows)!=3:raise ValueError('invalid_campaign_plan')
    plans=[sector_plan(v,allowed) for v in rows]
    if len({p['template'] for p in plans})!=3:raise ValueError('repeated_campaign_layout')
    if not all(plans[0]['armor'][team]['enabled'] for team in ('green','red')):raise ValueError('opening_requires_both_tanks')
    return {'sectors':plans,'strategy':str(value.get('strategy',''))[:240]}


def validate_layout(layout):
    if not isinstance(layout,dict) or set(layout)!={'theme','objective_z','components'} or layout['theme'] not in THEMES:raise ValueError('invalid_layout')
    def number(v):return type(v) in (int,float) and math.isfinite(v)
    if not number(layout['objective_z']) or abs(layout['objective_z'])>.9:raise ValueError('invalid_objective_z')
    rows=layout['components']
    if not isinstance(rows,list) or not 3<=len(rows)<=LIMITS["max_components"]:raise ValueError('invalid_component_count')
    for i,c in enumerate(rows):
        if not isinstance(c,dict) or set(c)!={'kind','x','z','width','depth'} or not isinstance(c['kind'],str) or c['kind'] not in COMPONENTS:raise ValueError('invalid_component')
        if not all(number(c[k]) for k in ('x','z','width','depth')):raise ValueError('invalid_component_bounds')
        x,z,w,d=(c[k] for k in ('x','z','width','depth'))
        if not (.04<=w<=LIMITS["max_component_width"] and .04<=d<=LIMITS["max_component_depth"] and .25<=x<=LENGTH-.20 and x-w/2>=.12 and x+w/2<=LENGTH-.10 and abs(z)+d/2<=1.32):raise ValueError('invalid_component_bounds')
        if abs(x-(LENGTH-.22))<w/2+.13 and abs(z-layout['objective_z'])<d/2+.13:raise ValueError('blocked_objective')
        for b in rows[:i]:
            if abs(x-b['x'])<(w+b['width'])/2+.04 and abs(z-b['z'])<(d+b['depth'])/2+.04:raise ValueError('overlapping_components')
    if sum(not COMPONENTS[c['kind']].get('no_slots') and c['kind']!='fuel_depot' for c in rows)<3:raise ValueError('unsafe_defender_station')
    return layout

def fit_campaign_layouts(value):
    """Editor snapping only: preserve types/sizes/roles, nudge overlapping footprints.

    Keep raw model output in the call log. Return every correction separately;
    this is never a seeded layout replacement or a new model decision.
    """
    import copy
    result=copy.deepcopy(value);adjustments=[]
    if not isinstance(result,dict) or not isinstance(result.get('sectors'),list):return result,adjustments
    for sector,p in enumerate(result['sectors']):
        if not isinstance(p,dict) or 'layout' not in p:continue
        layout=p['layout']
        try:validate_layout(layout);continue
        except ValueError as error:
            if str(error) not in ('overlapping_components','invalid_component_bounds','blocked_objective'):raise
        placed=[]
        for index,c in enumerate(layout['components']):
            # Individually check geometry and types, even if an earlier overlap
            # prevented the original validator from reaching this component.
            if not isinstance(c,dict) or set(c)!={'kind','x','z','width','depth'} or not isinstance(c['kind'],str) or c['kind'] not in COMPONENTS:raise ValueError('invalid_component')
            if not all(type(c[k]) in (int,float) and math.isfinite(c[k]) for k in ('x','z','width','depth')):raise ValueError('invalid_component_bounds')
            w,d=c['width'],c['depth']
            if not .04<=w<=LIMITS["max_component_width"] or not .04<=d<=LIMITS["max_component_depth"]:raise ValueError('invalid_component_bounds')
            def fits(x,z):
                return (.25<=x<=LENGTH-.20 and x-w/2>=.12 and x+w/2<=LENGTH-.10 and abs(z)+d/2<=1.32
                    and not(abs(x-(LENGTH-.22))<w/2+.13 and abs(z-layout['objective_z'])<d/2+.13)
                    and all(abs(x-b['x'])>=(w+b['width'])/2+.041 or abs(z-b['z'])>=(d+b['depth'])/2+.041 for b in placed))
            if not fits(c['x'],c['z']):
                candidates=sorted(((dx, dz) for dx in range(-7,8) for dz in range(-7,8) if dx*dx+dz*dz<=49),key=lambda q:(q[0]**2+q[1]**2,abs(q[0]),q))
                old=[c['x'],c['z']]
                match=next(((round(old[0]+dx*.05,5),round(old[1]+dz*.05,5)) for dx,dz in candidates if fits(round(old[0]+dx*.05,5),round(old[1]+dz*.05,5))),None)
                if match is None:raise ValueError('layout_packing_failed')
                c['x'],c['z']=match
                adjustments.append({'sector_offset':sector,'component':index,'from':old,'to':list(match),'reason':'editor_footprint_snap'})
            placed.append(c)
        validate_layout(layout)
    return result,adjustments


def validate_long_defense(plan):
    """Live slow-brain plans must actually occupy the expanded battle depth."""
    for sector in plan['sectors']:
        rows=sector['layout']['components']
        stations=[c for c in rows if not COMPONENTS[c['kind']].get('no_slots') and c['kind']!='fuel_depot'][:3]
        xs=[c['x'] for c in stations]
        if len(rows)<6 or min(xs)>LENGTH/3 or max(xs)<LENGTH*2/3 or max(xs)-min(xs)<LENGTH*.4:
            raise ValueError('spread_first_three_safe_stations_across_front_middle_rear')
        if not any(c['kind'] in ('sandbag','trench','wall') and max(c['width'],c['depth'])>=.65 for c in rows):
            raise ValueError('need_continuous_fortification_at_least_0.65m')
    return plan

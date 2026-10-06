#!/usr/bin/env python3
"""Build an offline, read-only reference database from licensed source snapshots.
Downloads are cached; publication is atomic and never touches the user's learning DB.
"""
import argparse,bz2,gzip,hashlib,json,re,sqlite3,subprocess,unicodedata,xml.etree.ElementTree as ET
from pathlib import Path
from datetime import datetime,timezone
ROOT=Path(__file__).resolve().parent.parent
SOURCES={
 'JMdict_e_examp.gz':'https://www.edrdg.org/pub/Nihongo/JMdict_e_examp.gz',
 'jpn_sentences_detailed.tsv.bz2':'https://downloads.tatoeba.org/exports/per_language/jpn/jpn_sentences_detailed.tsv.bz2',
 'OpenJLPT-NOTICE.md':'https://cdn.jsdelivr.net/gh/evanclan/OpenJLPT@main/NOTICE.md',
 'OpenJLPT-LICENSE.txt':'https://cdn.jsdelivr.net/gh/evanclan/OpenJLPT@main/LICENSE',
 'CC-BY-SA-4.0.txt':'https://creativecommons.org/licenses/by-sa/4.0/legalcode.txt',
 'CC-BY-2.0-FR.html':'https://creativecommons.org/licenses/by/2.0/fr/legalcode',
 'EDRDG-LICENSE.html':'https://www.edrdg.org/edrdg/licence.html',
 **{f'openjlpt-n{i}.json':f'https://cdn.jsdelivr.net/gh/evanclan/OpenJLPT@main/data/json/vocab/n{i}.json' for i in range(1,6)}}
def norm(s):return unicodedata.normalize('NFKC',s).strip()
def text(e,t):return e.findtext(t,'').strip()
def texts(e,t):return [x.text.strip() for x in e.findall(t) if x.text and x.text.strip()]
def build(cache,out):
 for name in SOURCES:
  if not (cache/name).is_file():raise ValueError(f'Missing complete source: {name}')
 if 'CC BY-SA' not in (cache/'OpenJLPT-NOTICE.md').read_text():raise ValueError('Unexpected attribution notice')
 levels={};level_count=0
 for i in range(1,6):
  for v in json.loads((cache/f'openjlpt-n{i}.json').read_text()):
   if v.get('level')!=f'N{i}':raise ValueError('Unexpected level')
   if isinstance(v.get('jmdict_id'),int):
    levels.setdefault(v['jmdict_id'],[]).append(v);level_count+=1
 authors={}
 with bz2.open(cache/'jpn_sentences_detailed.tsv.bz2','rt') as f:
  for line in f:
   row=line.rstrip('\n').split('\t')
   if len(row)>=4 and row[1]=='jpn' and row[3] not in ('','\\N'):authors[row[0]]=(row[2],row[3])
 out.mkdir(parents=True,exist_ok=True);tmp=out/'reference.sqlite.tmp';tmp.unlink(missing_ok=True)
 db=sqlite3.connect(tmp)
 db.executescript('''PRAGMA journal_mode=OFF; CREATE TABLE entries(id INTEGER PRIMARY KEY,payload TEXT NOT NULL);
 CREATE TABLE forms(form TEXT NOT NULL,entry_id INTEGER NOT NULL,PRIMARY KEY(form,entry_id));
 CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL); PRAGMA user_version=1;''')
 count=excount=graded=skipped=0
 try:
  with gzip.open(cache/'JMdict_e_examp.gz','rb') as stream:
   for event,e in ET.iterparse(stream,events=('end',)):
    if e.tag!='entry':continue
    eid=int(text(e,'ent_seq'));words=texts(e,'k_ele/keb');readings=texts(e,'r_ele/reb');forms=words+readings
    senses=[];previous_pos=[]
    for index,sense in enumerate(e.findall('sense')):
     pos=texts(sense,'pos') or previous_pos;previous_pos=pos
     examples=[]
     for ex in sense.findall('example'):
      src=ex.find('ex_srce');sid=src.text.strip() if src is not None and src.text else ''
      jpn=next((a.text for a in ex.findall('ex_sent') if a.get('{http://www.w3.org/XML/1998/namespace}lang')=='jpn'),'')
      hit=text(ex,'ex_text');owner=authors.get(sid)
      if src is None or src.get('exsrc_type')!='tat' or not owner or owner[0]!=jpn or not hit or hit not in jpn:
       skipped+=1;continue
      examples.append({'sentence_id':sid,'ja':jpn,'matched_text':hit,'author':owner[1],
       'url':f'https://tatoeba.org/en/sentences/show/{sid}','license':'CC BY 2.0 FR','review_status':'dictionary_linked_not_independently_reviewed'})
     gloss=[a.text for a in sense.findall('gloss') if a.text and a.get('{http://www.w3.org/XML/1998/namespace}lang','eng')=='eng']
     senses.append({'number':index+1,'glosses':gloss,'pos':pos,'notes':texts(sense,'s_inf'),
       'register':texts(sense,'misc'),'fields':texts(sense,'field'),'dialect':texts(sense,'dial'),
       'only_spellings':texts(sense,'stagk'),'only_readings':texts(sense,'stagr'),
       'examples':examples})
     excount+=len(examples)
    matches=[v for v in levels.get(eid,[]) if norm(v['word']) in map(norm,forms) and norm(v['reading']) in map(norm,readings)]
    refs=sorted({v['level'] for v in matches})
    if refs:graded+=1
    payload={'id':eid,'spellings':words,'readings':readings,'senses':senses,'reference_levels':refs,
     'reference_level_matches':[{'word':v['word'],'reading':v['reading'],'level':v['level']} for v in matches],
     'level_source':'OpenJLPT / Jonathan Waller (非官方参考)' if refs else '',
     'source_url':f'https://www.edrdg.org/jmdictdb/cgi-bin/entr.py?svc=jmdict&seq={eid}',
     'license':'CC BY-SA 4.0'}
    db.execute('INSERT INTO entries VALUES(?,?)',(eid,json.dumps(payload,ensure_ascii=False,separators=(',',':'))))
    db.executemany('INSERT OR IGNORE INTO forms VALUES(?,?)',[(norm(w),eid) for w in forms])
    count+=1;e.clear()
  manifest={'format_version':1,'built_at':datetime.now(timezone.utc).isoformat(),'entries':count,'linked_examples':excount,
    'graded_entries':graded,'skipped_examples':skipped,'languages':['Japanese','English'],
    'example_policy':'Only JMdict sense-indexed Japanese examples with exact current Tatoeba text and a named contributor; no OpenJLPT auto-matched examples.',
    'sources':[{'file':name,'url':url,'sha256':hashlib.sha256((cache/name).read_bytes()).hexdigest()} for name,url in SOURCES.items()]}
  # Generation date is retained from the actual upstream XML header when available.
  with gzip.open(cache/'JMdict_e_examp.gz','rt') as f:header=f.read(35000)
  manifest['jmdict_header_dates']=re.findall(r'\d{4}-\d{2}-\d{2}',header)[:8]
  db.execute('INSERT INTO metadata VALUES(?,?)',('manifest',json.dumps(manifest,ensure_ascii=False)))
  db.commit();assert db.execute('PRAGMA integrity_check').fetchone()[0]=='ok';db.close()
  tmp.replace(out/'reference.sqlite')
  (out/'reference-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
  licenses=out/'licenses';licenses.mkdir(exist_ok=True)
  for name in ('OpenJLPT-NOTICE.md','OpenJLPT-LICENSE.txt','CC-BY-SA-4.0.txt','CC-BY-2.0-FR.html','EDRDG-LICENSE.html'):
   (licenses/name).write_bytes((cache/name).read_bytes())
  print(json.dumps({k:manifest[k] for k in ('entries','linked_examples','graded_entries','skipped_examples')},ensure_ascii=False))
 except Exception:
  db.close();tmp.unlink(missing_ok=True);raise
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--cache',type=Path,default=ROOT/'.build/reference-sources');p.add_argument('--output',type=Path,default=ROOT/'resources/learning/reference');p.add_argument('--download',action='store_true');args=p.parse_args()
 if args.download:
  args.cache.mkdir(parents=True,exist_ok=True)
  for name,url in SOURCES.items():
   target=args.cache/name;partial=target.with_suffix(target.suffix+'.part')
   subprocess.run(['curl','--fail','--location','--retry','2','--max-time','600',url,'-o',str(partial)],check=True)
   partial.replace(target)
 build(args.cache,args.output)

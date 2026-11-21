from pathlib import Path
import re,json,sys
from lupa import lua51
LUA=lua51.LuaRuntime()
TOKEN=re.compile(r'--\[\[.*?\]\]|--[^\n]*|\[\[.*?\]\]|"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'|[A-Za-z_][A-Za-z_0-9]*|\.\.|==|~=|<=|>=|\S',re.S)
def string(t):
 try:return LUA.execute('return '+t)
 except:return None

def prose(s):
 return bool(re.search('[A-Za-z]',re.sub(r'%%|%[-+#0 ]*[0-9]*(?:\.[0-9]+)?[cdiouxXeEfgGqs]','',s)))
CALLS={'ShowExport':[2],'PrintDiff':[1],'emit':[0],'Print':[0],'SetText':[0],'AddLine':[0],'SetTitle':[0],'SetFormattedText':[0],'MakeButton':[1],'MakeCheck':[1],'Tip':[1,2],'section':[1]}

def candidates(source):
  toks=[m for m in TOKEN.finditer(source) if not m.group().startswith('--')]
  localized=set();stack=[]
  for n,tok in enumerate(toks):
    v=tok.group()
    if v in ('(','[','{'):stack.append(v=='[' and n>0 and toks[n-1].group()=='L' or bool(stack and stack[-1]))
    elif v in (')',']','}'):
      if stack:stack.pop()
    elif stack and stack[-1]:localized.add(n)
  found=[]
  for i,t in enumerate(toks[:-1]):
    if t.group() not in CALLS or toks[i+1].group()!='(':continue
    if i and toks[i-1].group()=='function':continue
    start=i+2;depth=0;arg=0
    for j in range(start,len(toks)):
      q=toks[j];v=q.group()
      if v in ('(', '[','{'):depth+=1
      elif v in (')',']','}'):
        if depth==0:break
        depth-=1
      if v==',' and depth==0:arg+=1;continue
      if arg not in CALLS[t.group()] or not v.startswith(('"',"\'")):continue
      text=string(v)
      if not isinstance(text,str) or not prose(text):continue
      # L lookup and nested machine API arguments are independently catalogued.
      if j in localized:continue
      if j and toks[j-1].group() in {"==","~="}:continue
      found.append((source.count('\n',0,q.start())+1,t.group(),text))
  return found

def check(root):
  import importlib.util
  spec=importlib.util.spec_from_file_location("localecheck",root/"tools/localecheck.py")
  gate=importlib.util.module_from_spec(spec);spec.loader.exec_module(gate)
  english_table=gate.english_table
  allowed=json.loads((root/'tools/localization-exceptions.json').read_text(encoding='utf-8'))
  baseline=json.loads((root/'tools/locale-baseline-keys.json').read_text(encoding='utf-8'))
  english=english_table(root/'BuffRadar/BuffRadar.lua')
  errors=[]
  dynamic=json.loads((root/"tools/localization-dynamic-labels.json").read_text(encoding="utf-8"))
  for owner,keys in dynamic.items():
    for key in keys:
      if key not in english:errors.append(owner+": dynamic locale key missing "+repr(key))
  for key in baseline:
    if key not in english:errors.append('original locale key lost: '+repr(key))
  for path in sorted((root/'BuffRadar').rglob('*.lua')):
    source=path.read_text(encoding='utf-8-sig')
    for corrupt in ('Â·','â€“','â€”','\ufffd'):
      if corrupt in source:errors.append(str(path.relative_to(root))+': corrupt UTF-8 sequence '+repr(corrupt))
    if path.parent.name=='Locales' or path.name=='Data.lua':continue
    for line,call,text in candidates(source):
      if text not in allowed.get(path.name,{}):errors.append(f'{path.name}:{line} {call}: visible literal {text!r}')
  for item in errors:print(item)
  print(f'Localization callsites: {len(errors)} errors; {len(baseline)} original keys retained')
  return int(bool(errors))

if __name__=='__main__':
  sys.exit(check(Path(__file__).resolve().parents[1]))

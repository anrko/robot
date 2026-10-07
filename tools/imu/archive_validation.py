"""Archive completed simulation summaries and Gowin demo build for review."""
from pathlib import Path
import hashlib
import html
import json
import re
import shutil
import zipfile
import xml.etree.ElementTree as ET
from validate import ROOT


def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()


def main():
    results=ROOT/'sim/imu/results';docs=ROOT/'docs/imu';docs.mkdir(parents=True,exist_ok=True)
    reports={name:json.loads((results/f'{name}_summary.json').read_text())
             for name in ('upstream','euler','math','demo')}
    reports['core']=json.loads((results/'summary.json').read_text())
    assert all(reports[x]['passed'] for x in ('core','euler','math','demo'))
    pnr=ROOT/'impl/pnr'
    timing=pnr/'camera720_imu_demo_tr_content.html'
    raw=timing.read_text()
    text=html.unescape(re.sub('<[^>]*>',' ',raw))
    lines=[re.sub(r'\s+',' ',x).strip() for x in text.splitlines() if x.strip()]
    def following(label):return lines[lines.index(label)+1]
    violated_setup=int(following('Numbers of Setup Violated Endpoints'))
    violated_hold=int(following('Numbers of Hold Violated Endpoints'))
    start=lines.index('Actual Fmax')+3
    fmax=[]
    for i in range(start,len(lines)):
        if lines[i]=='Total Negative Slack Summary:':break
        if re.fullmatch(r'\d+\.\d+\(MHz\)',lines[i]) and i+1<len(lines) and '(MHz)' in lines[i+1]:
            fmax.append({'clock':lines[i-1],'constraint_mhz':float(lines[i].split('(')[0]),
                         'actual_mhz':float(lines[i+1].split('(')[0])})
    assert fmax and all(x['actual_mhz']>=x['constraint_mhz'] for x in fmax),'Fmax failed'
    assert violated_setup==0 and violated_hold==0,'Timing violations remain'
    resource_text=(pnr/'camera720_imu_demo.rpt.txt').read_text()
    resources={}
    for name in ('Logic','Register','BSRAM','DSP'):
        match=re.search(r'^\s*'+name+r'\s*\|\s*([\d.]+)/([\d.]+)',resource_text,re.M)
        assert match;resources[name]={'used':float(match[1]),'available':float(match[2])}
    reports['gowin']={'tool':'V1.9.12.03','part':'GW5AT-LV60PG484AC1/I0',
        'created':following('Created Time'),'setup_violated_endpoints':violated_setup,
        'hold_violated_endpoints':violated_hold,'fmax':fmax,'resources':resources,
        'remaining_warning':'PR1014: clk50m_d uses generic routing; board validation required.'}
    release=ROOT/'release';fs=release/'camera720_cam2_720p_imu_demo.fs'
    # Gowin marks generated bitstreams read-only. Keep the release copy writable
    # so archiving a later build can update it without changing the source output.
    if fs.exists():fs.chmod(0o666)
    shutil.copyfile(pnr/'camera720_imu_demo.fs',fs)
    (release/(fs.name+'.sha256')).write_text(f'{digest(fs)}  {fs.name}\n',encoding='ascii')
    reports['bitstream']={'path':str(fs.relative_to(ROOT)).replace('\\','/'),'sha256':digest(fs)}
    source_paths=set((ROOT/'src/imu').glob('*.v')) | set((ROOT/'src/imu').glob('*.hex'))
    for project in ('camera720.gprj','camera720_imu_demo.gprj'):
        source_paths.add(ROOT/project)
        source_paths.update(ROOT/n.attrib['path'] for n in ET.parse(ROOT/project).findall('.//File'))
    reports['source_sha256']={str(p.relative_to(ROOT)).replace('\\','/'):digest(p) for p in sorted(source_paths)}
    (docs/'validation_summary.json').write_text(json.dumps(reports,indent=2,ensure_ascii=False),encoding='utf-8')
    shutil.copy2(results/'comparison.png',docs/'comparison.png')
    shutil.copy2(timing,docs/'gowin_timing.html')
    shutil.copy2(pnr/'camera720_imu_demo.rpt.txt',docs/'gowin_resources.txt')
    # Include exactly the project dependencies and IMU development collateral.
    include={ROOT/'camera720_imu_demo.gprj',ROOT/'camera720.gprj',fs,release/(fs.name+'.sha256'),
        ROOT/'tools/build_camera720_imu_demo.tcl',ROOT/'tools/build_camera720.tcl',ROOT/'src/README.md',
        ROOT/'.gitignore',ROOT/'.gitattributes',ROOT/'CAMERA720_CAM2_烧录说明.md'}
    for project in ('camera720.gprj','camera720_imu_demo.gprj'):
        for node in ET.parse(ROOT/project).findall('.//File'):
            include.add(ROOT/node.attrib['path'])
    for directory in ('src/imu','tools/imu','docs/imu'):
        include.update(p for p in (ROOT/directory).rglob('*') if p.is_file() and '__pycache__' not in p.parts)
    include.update((ROOT/'sim/imu').glob('*.v'))
    include.update((ROOT/'sim/imu').glob('*.sv'))
    archive=release/'camera720_imu_demo_project.zip'
    with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for p in sorted(include):z.write(p,p.relative_to(ROOT).as_posix())
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        assert hashlib.sha256(z.read(fs.relative_to(ROOT).as_posix())).hexdigest().upper()==digest(fs)
    sums=release/'SHA256SUMS.txt'
    old=sums.read_text(encoding='ascii').splitlines()
    targets=(fs.name,archive.name)
    old=[row for row in old if not any(row.endswith(name) for name in targets)]
    sums.write_text('\n'.join(old+[f'{digest(release/name)}  {name}' for name in targets])+'\n',encoding='ascii')
    print(json.dumps({'bitstream':str(fs),'sha256':digest(fs),'archive':str(archive),'gowin':reports['gowin']},ensure_ascii=False))


if __name__=='__main__':main()

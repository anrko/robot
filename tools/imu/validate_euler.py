"""Validate quaternion-to-Euler and BCD, using Python trig ground truth."""
from pathlib import Path
import json
import random
import math
import numpy as np
from reference import SCALE,from_euler,euler
from validate import ROOT,run


def main():
    out=ROOT/'sim/imu/results';out.mkdir(parents=True,exist_ok=True)
    rng=random.Random(8899)
    angles=[(0,0,0),(0,0,180),(0,0,-179.9),(30,-20,70),(-45,60,-100)]
    angles += [(r,p,y) for r in (-150,0,45) for p in (-89.9,-85,0,85,89.9) for y in (-170,0,130)]
    angles += [tuple(rng.uniform(-a,a) for a in (179.9,85,179.9)) for _ in range(600)]
    raw=[tuple(round(x*SCALE) for x in from_euler(*a)) for a in angles]
    # Replay every quaternion from the core comparison if available.
    if (out/'rtl.csv').exists():
        raw += [tuple(int(x) for x in row[1:5]) for row in np.loadtxt(out/'rtl.csv',delimiter=',',ndmin=2)]
    with (out/'euler_vectors.txt').open('w',encoding='ascii') as f:
        for q in raw:f.write(' '.join(map(str,q))+'\n')
    rtl=[ROOT/'src/imu'/x for x in ('isqrt_u66.v','atan2_cordic.v','quaternion_euler.v','angle_bcd.v')]
    run(['iverilog','-g2012','-s','tb_euler_compare','-o',out/'euler.vvp',*rtl,ROOT/'sim/imu/tb_euler_compare.v'])
    run(['vvp',out/'euler.vvp',f'+INPUT={(out/"euler_vectors.txt").as_posix()}',f'+OUTPUT={(out/"euler_rtl.csv").as_posix()}'])
    values=np.loadtxt(out/'euler_rtl.csv',delimiter=',',ndmin=2)
    assert len(values)==len(raw)
    expected=np.array([euler(tuple(x/SCALE for x in q)) for q in raw])
    actual=values[:,:3]/10
    error=np.abs((actual-expected+180)%360-180)
    # atan2 is inherently ambiguous at the Euler singularity +/-90 pitch;
    # near-singularity vectors stop at 89.9 degrees to test conditioning.
    max_error=np.max(error,axis=0)
    for row in values:
        for i in range(3):
            digits=f'{abs(int(row[i])):04d}'
            assert int(row[i+3])==int(digits,16),'BCD digit mismatch'
            assert bool(row[i+6])==(row[i]<0),'BCD sign mismatch'
    report={'passed':bool(max(max_error)<0.11),'samples':len(raw),
            'max_error_deg_roll_pitch_yaw':max_error.tolist(),'threshold_deg':0.11,
            'max_cycles':int(max(values[:,9]))}
    (out/'euler_summary.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report));assert report['passed'],'Euler precision failed'


if __name__=='__main__':main()

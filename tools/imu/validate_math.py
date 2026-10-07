"""Exact integer normaliser checks and asynchronous OSD mailbox simulation."""
import json
import math
import random
import numpy as np
from validate import ROOT,run


def main():
    out=ROOT/'sim/imu/results';out.mkdir(parents=True,exist_ok=True)
    rng=random.Random(6624)
    cases=[(0,0,0,0),(3,4,0,0),(1<<24,0,0,0),(-(1<<24),0,0,0),
           (-(1<<31),)*4,((1<<31)-1,)*4,(128,1,2,3),(1,1,1,1)]
    cases += [tuple(rng.randint(-(1<<31),(1<<31)-1) for _ in range(4)) for _ in range(180)]
    (out/'norm_vectors.txt').write_text(''.join(' '.join(map(str,v))+'\n' for v in cases),encoding='ascii')
    run(['iverilog','-g2012','-s','tb_normalize','-o',out/'norm.vvp',ROOT/'src/imu/isqrt_u66.v',
         ROOT/'src/imu/normalize_q24.v',ROOT/'sim/imu/tb_normalize.v'])
    run(['vvp',out/'norm.vvp',f'+INPUT={(out/"norm_vectors.txt").as_posix()}',f'+OUTPUT={(out/"norm_rtl.csv").as_posix()}'])
    rows=np.loadtxt(out/'norm_rtl.csv',delimiter=',',dtype=np.int64,ndmin=2)
    assert len(rows)==len(cases)
    for v,row in zip(cases,rows):
        mag=math.isqrt(sum(x*x for x in v))
        norm=tuple((-1 if x<0 else 1)*((abs(x)<<24)//mag) for x in v) if mag else (0,)*4
        assert tuple(row)==(mag,int(mag==0),*norm),(v,row,mag,norm)
    run(['iverilog','-g2012','-s','tb_osd_cdc','-o',out/'cdc.vvp',ROOT/'src/imu/osd_attitude_cdc.v',ROOT/'sim/imu/tb_osd_cdc.v'])
    run(['vvp',out/'cdc.vvp'])
    run(['iverilog','-g2012','-s','tb_eth_reset','-o',out/'eth_reset.vvp',
         ROOT/'src/camera720/camera_single/eth_tx_ctrl/eth_tx_ctrl.v',ROOT/'sim/imu/tb_eth_reset.v'])
    run(['vvp',out/'eth_reset.vvp'])
    report={'passed':True,'normalizer_vectors':len(cases),'normalizer_bit_exact':True,
            'cdc_mailbox_frame_latching_stopped_clock_reset':True,'ethernet_reset_release':True}
    (out/'math_summary.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps(report))


if __name__=='__main__':main()

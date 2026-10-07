"""End-to-end demo source/RTL/CDC/OSD check for two ROM wraps."""
import json
import csv
import math
import numpy as np
from reference import SCALE,step,euler,from_euler
from validate import ROOT,run,error_deg


def decode_bcd(word,negative):
    digits=[(word>>(4*j))&15 for j in range(4)]
    assert all(x<10 for x in digits),'invalid display digit'
    angle=sum(x*10**j for j,x in enumerate(digits))/10
    return -angle if negative else angle


def main():
    out=ROOT/'sim/imu/results';out.mkdir(parents=True,exist_ok=True)
    rtl=[ROOT/'src/imu'/x for x in ('isqrt_u66.v','normalize_q24.v','madgwick_imu.v','atan2_cordic.v',
         'quaternion_euler.v','angle_bcd.v','attitude_pipeline.v','imu_demo_source.v','osd_attitude_cdc.v')]
    run(['iverilog','-g2012','-s','tb_demo_pipeline','-o',out/'demo.vvp',*rtl,
         ROOT/'src/camera720/attitude_osd_rgb565.v',ROOT/'sim/imu/tb_demo_pipeline.v'])
    run(['vvp',out/'demo.vvp',f'+OUTPUT={(out/"demo_rtl.csv").as_posix()}'])
    samples=[]
    for line in (ROOT/'src/imu/demo_samples.hex').read_text().splitlines():
        row=[]
        for j in range(6):
            value=int(line[j*8:(j+1)*8],16);row.append((value-(1<<32) if value&(1<<31) else value)/SCALE)
        samples.append(row)
    q=(1.,0.,0.,0.);refs=[];display=[];rtl_q=[];truth=[]
    with (out/'demo_rtl.csv').open() as f:
        for i,row in enumerate(csv.reader(f)):
            assert int(row[0])==i
            a=samples[i%1024];q=step(q,a[:3],a[3:],167772/SCALE);refs.append(q)
            packed=int(row[1]);rtl_q.append([int(x)/SCALE for x in row[2:6]])
            display.append([decode_bcd((packed>>shift)&65535,(packed>>(shift+16))&1) for shift in (34,17,0)])
            phase=2*math.pi*((i+1)%1024)/1024
            truth.append(from_euler(*(a*math.sin(phase) for a in (25,15,30))))
    assert len(refs)==2048
    numeric=error_deg(rtl_q,refs);physical=error_deg(rtl_q,truth)
    display_error=np.abs((np.asarray(display)-np.asarray([euler(q) for q in refs])+180)%360-180)
    report={'passed':bool(max(numeric)<0.35 and np.max(display_error)<0.4),
            'samples':2048,'rom_wraps':2,'max_rtl_float_deg':float(max(numeric)),
            'max_display_float_deg':float(np.max(display_error)),'max_synthetic_truth_deg':float(max(physical)),
            'threshold_rotation_deg':0.35,'threshold_display_deg':0.4,
            'scope':'Synthetic 100 Hz samples through the complete RTL pipeline; not BMI088 hardware.'}
    (out/'demo_summary.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report));assert report['passed'],'demo mismatch'


if __name__=='__main__':main()

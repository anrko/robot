"""Generate synthetic IMU vectors, run Icarus and compare to float reference.

Run from any directory: python tools/imu/validate.py
The same quantised input and sample period are supplied to Python and RTL.
Pass criteria are declared before simulation, not fitted to the results.
"""
from pathlib import Path
import argparse
import csv
import json
import math
import random
import subprocess
import numpy as np
from reference import SCALE,step,gravity,advance_truth,from_euler,euler

ROOT=Path(__file__).resolve().parents[2]
LIMIT_DEG=0.25
NORM_LIMIT=2e-6


def scenarios():
    rng=random.Random(88088)
    cases=[]
    def add(name,n,rate,noise=False,zero_acc=False,variable_dt=False):
        truth=(1.,0.,0.,0.);rows=[]
        for i in range(n):
            dt=(0.001+0.001*(i%4)) if variable_dt else 0.002
            g=rate(i*0.002) if callable(rate) else rate
            a=(0.,0.,0.) if zero_acc else gravity(truth)
            gm=g
            if noise:
                a=tuple(x+rng.gauss(0,0.01) for x in a)
                gm=tuple(x+rng.gauss(0,0.002) for x in g)
            raw=tuple(round(x*SCALE) for x in (*a,*gm,dt))
            truth=advance_truth(truth,g,raw[-1]/SCALE)
            rows.append((raw,truth))
        cases.append((name,rows,True))
    add('stationary',700,(0,0,0))
    add('yaw_positive',1600,(0,0,1))
    add('yaw_negative',1000,(0,0,-1))
    add('roll_rotation',800,(0.65,0,0))
    add('pitch_rotation',700,(0,-0.5,0))
    add('coupled_motion',2400,lambda t:(0.3*math.sin(t),0.25*math.cos(0.7*t),0.4))
    add('sensor_noise',1600,lambda t:(0.2*math.sin(t),0.2*math.cos(t),0.3),noise=True)
    add('missing_acceleration',1000,(0.4,-0.2,0.6),zero_acc=True)
    add('variable_dt',1200,(0.3,-0.2,0.5),variable_dt=True)
    # Static tilt: convergence from identity, so early outputs are not truth.
    for name,angles in [('tilt_convergence',(30,-20,0)),('negative_tilt',(-35,25,0))]:
        q=from_euler(*angles);raw=tuple(round(x*SCALE) for x in (*gravity(q),0,0,0,0.002))
        cases.append((name,[(raw,q)]*2600,False))
    return cases


def run(cmd):
    subprocess.run([str(x) for x in cmd],cwd=ROOT,check=True)


def error_deg(a,b):
    # q and -q describe the same attitude. Use the full rotation error,
    # not raw quaternion subtraction or wrapped Euler subtraction.
    a=np.asarray(a,dtype=float);b=np.asarray(b,dtype=float)
    a=a/np.linalg.norm(a,axis=1)[:,None];b=b/np.linalg.norm(b,axis=1)[:,None]
    return np.degrees(2*np.arccos(np.clip(np.abs(np.sum(a*b,axis=1)),0,1)))


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--out',default='sim/imu/results')
    args=parser.parse_args();out=(ROOT/args.out).resolve();out.mkdir(parents=True,exist_ok=True)
    cases=scenarios();refs=[];truths=[];names=[];ranges=[]
    with (out/'vectors.txt').open('w',encoding='ascii') as stream:
        for name,rows,track_truth in cases:
            q=(1.,0.,0.,0.);start=len(refs)
            for i,(raw,truth) in enumerate(rows):
                stream.write(' '.join(str(x) for x in (int(i==0),*raw))+'\n')
                vals=tuple(x/SCALE for x in raw)
                q=step(q,vals[:3],vals[3:6],vals[6]);refs.append(q);truths.append(truth);names.append(name)
            ranges.append((name,start,len(refs),track_truth))
    rtl=[ROOT/'src/imu'/x for x in ('isqrt_u66.v','normalize_q24.v','madgwick_imu.v')]
    run(['iverilog','-g2012','-Wall','-s','tb_madgwick_compare','-o',out/'compare.vvp',*rtl,ROOT/'sim/imu/tb_madgwick_compare.v'])
    run(['vvp',out/'compare.vvp',f'+INPUT={(out/"vectors.txt").as_posix()}',f'+OUTPUT={(out/"rtl.csv").as_posix()}'])
    values=np.loadtxt(out/'rtl.csv',delimiter=',',ndmin=2)
    if len(values)!=len(refs):raise AssertionError('lost/duplicated samples')
    if not np.array_equal(values[:,0],np.arange(len(refs))):raise AssertionError('sample order changed')
    rtl_q=values[:,1:5]/SCALE
    ref_error=error_deg(rtl_q,refs);truth_error=error_deg(rtl_q,truths)
    norm_error=np.abs(np.linalg.norm(rtl_q,axis=1)-1)
    summary=[];fail=[]
    for name,start,end,track_truth in ranges:
        row={'scenario':name,'samples':end-start,'max_rtl_float_deg':float(max(ref_error[start:end])),
             'rms_rtl_float_deg':float(np.sqrt(np.mean(ref_error[start:end]**2))),
             'max_norm_error':float(max(norm_error[start:end])),
             'max_core_cycles':int(max(values[start:end,5])),
             'final_euler_deg':euler(rtl_q[end-1])}
        if track_truth:
            row['max_truth_deg']=float(max(truth_error[start:end]))
            # Noisy case is an algorithm behaviour check, not a sensor accuracy claim.
            if not name=='sensor_noise' and row['max_truth_deg']>0.3:fail.append(name+': truth')
        else:
            target=euler(truths[end-1]);final=row['final_euler_deg']
            row['final_tilt_error_deg']=max(abs(final[j]-target[j]) for j in (0,1))
            if row['final_tilt_error_deg']>0.15:fail.append(name+': convergence')
        if row['max_rtl_float_deg']>LIMIT_DEG:fail.append(name+': reference')
        if row['max_norm_error']>NORM_LIMIT:fail.append(name+': norm')
        summary.append(row)
        print(f"{name:24} max RTL/float={row['max_rtl_float_deg']:.6f} deg, cycles={row['max_core_cycles']}")
    report={'passed':not fail,'samples':len(refs),'threshold_deg':LIMIT_DEG,'norm_threshold':NORM_LIMIT,
            'failures':fail,'scenarios':summary,'scope':'Synthetic quantised inputs; no real BMI088 or magnetic heading validation.'}
    (out/'summary.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    with (out/'comparison.csv').open('w',newline='',encoding='utf-8') as f:
        writer=csv.writer(f);writer.writerow(['sample','scenario','qw','qx','qy','qz','reference_error_deg','truth_error_deg','norm_error'])
        for i,q in enumerate(rtl_q):writer.writerow([i,names[i],*q,ref_error[i],truth_error[i],norm_error[i]])
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    fig,axes=plt.subplots(2,1,figsize=(11,6),sharex=True,layout='constrained')
    axes[0].plot(ref_error,lw=.7);axes[0].axhline(LIMIT_DEG,color='red',ls='--',label='Acceptance limit')
    axes[0].set_ylabel('RTL vs float (degrees)');axes[0].legend()
    axes[1].plot(norm_error,lw=.7);axes[1].set_ylabel('Quaternion norm error');axes[1].set_xlabel('Sample (reset between scenarios)')
    for _,start,_,_ in ranges:
        for ax in axes:ax.axvline(start,color='gray',alpha=.25,lw=.6)
    fig.savefig(out/'comparison.png',dpi=160);plt.close(fig)
    print(json.dumps({'passed':not fail,'samples':len(refs),'failures':fail}))
    if fail:raise SystemExit(1)


if __name__=='__main__':main()

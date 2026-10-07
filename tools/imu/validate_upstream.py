"""Record the original MQFU default configuration's no-rotation regression.

This is a diagnostic specimen, not the production RTL or an expected-good test.
An unchanged identity quaternion after nonzero gyro is the recorded defect.
"""
import subprocess
import json
import re
from validate import ROOT,run


def main():
    out=ROOT/'sim/imu/results';out.mkdir(parents=True,exist_ok=True)
    vendor=ROOT/'src/imu/vendor/mqfu'
    run(['iverilog','-g2012','-I',vendor,'-s','review_mqfu_smoke','-o',out/'upstream.vvp',
         vendor/'madgwick.sv',*[vendor/f for f in ('fastInvSqrt.sv','newtonRaphson.sv','fixToSingle.sv','singleToFix.sv')],
         ROOT/'sim/imu/tb_upstream_smoke.sv'])
    result=subprocess.run(['vvp',str(out/'upstream.vvp')],cwd=ROOT,check=True,capture_output=True,text=True)
    (out/'upstream.log').write_text(result.stdout,encoding='utf-8')
    rows=re.findall(r'sample=(\d+) q=(-?\d+),(-?\d+),(-?\d+),(-?\d+) gyro_z=(-?\d+) half_qw=(-?\d+) qdot_z=(-?\d+)',result.stdout)
    assert len(rows)==16
    rotating=[tuple(map(int,r)) for r in rows if int(r[5])!=0]
    bug=all(r[1:5]==(16384,0,0,0) and r[-1]==0 for r in rotating)
    report={'original_default_bug_reproduced':bug,'samples':16,'rotating_samples':len(rotating),
            'gyro_z_rad_s':1,'observed_quaternion_q14':[int(x) for x in rows[-1][1:5]],
            'observed_qdot_z':int(rows[-1][-1]),'diagnostic_only':True}
    (out/'upstream_summary.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report));assert bug,'Original snapshot changed; re-review baseline'


if __name__=='__main__':main()

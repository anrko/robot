"""Generate coherent gravity/body-rate samples from analytic periodic Euler motion.

This creates FPGA ROM data, not a true sensor or a display-only angle animation.
The ROM is driven through the actual Madgwick and Euler RTL.
"""
from pathlib import Path
import math
from reference import SCALE,from_euler,gravity

ROOT=Path(__file__).resolve().parents[2]
PERIOD=1024*(167772/SCALE)


def main():
    lines=[]
    for i in range(1024):
        phase=2*math.pi*i/1024;rate=2*math.pi/PERIOD
        r,p,y=(math.radians(a)*math.sin(phase) for a in (25,15,30))
        rd,pd,yd=(math.radians(a)*math.cos(phase)*rate for a in (25,15,30))
        g=(rd-yd*math.sin(p),pd*math.cos(r)+yd*math.sin(r)*math.cos(p),
           -pd*math.sin(r)+yd*math.cos(r)*math.cos(p))
        a=gravity(from_euler(*(math.degrees(x) for x in (r,p,y))))
        words=[round(x*SCALE)&0xffffffff for x in (*a,*g)]
        lines.append(''.join(f'{x:08x}' for x in words))
    (ROOT/'src/imu/demo_samples.hex').write_text('\n'.join(lines)+'\n',encoding='ascii')
    print('Generated 1024 synthetic IMU samples, 100 Hz, periodic 10.24 s motion')


if __name__=='__main__':main()

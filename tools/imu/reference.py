"""Independent double-precision, six-axis Madgwick reference.

Hamilton quaternion (w,x,y,z), body-to-world, body gravity measurement +Z
at identity. Gyroscope is rad/s; dt is seconds. Exact math.sqrt is used,
not the upstream fixedpoint Python model or RTL's integer arithmetic.
"""
import math

SCALE = 1 << 24
GRAD_EPS = 128 / SCALE
BETA = 1677722 / SCALE


def unit(v):
    mag = math.sqrt(sum(x*x for x in v))
    return tuple(x / mag for x in v) if mag else tuple(0.0 for _ in v)


def gravity(q):
    w, x, y, z = q
    return (2*(x*z-w*y), 2*(w*x+y*z), 1-2*(x*x+y*y))


def multiply(a, b):
    w,x,y,z=a;v,i,j,k=b
    return (w*v-x*i-y*j-z*k,w*i+x*v+y*k-z*j,
            w*j-x*k+y*v+z*i,w*k+x*j-y*i+z*v)


def advance_truth(q, gyro, dt):
    """Analytic quaternion exponential for constant body rate over this step."""
    speed=math.sqrt(sum(x*x for x in gyro))
    if not speed:return q
    half=speed*dt/2
    delta=(math.cos(half), *(x*math.sin(half)/speed for x in gyro))
    return unit(multiply(q,delta))


def step(q, acc, gyro, dt, beta=BETA):
    # General Hamilton product, rather than the RTL microinstruction sequence.
    qdot=tuple(0.5*x for x in multiply(q,(0.0,*gyro)))
    if any(acc):
        w,x,y,z=q
        a=unit(acc)
        residual=tuple(p-m for p,m in zip(gravity(q),a))
        jacobian=((-2*y,2*z,-2*w,2*x),(2*x,2*w,2*z,2*y),(0,-4*x,-4*y,0))
        grad=tuple(sum(jacobian[j][i]*residual[j] for j in range(3)) for i in range(4))
        if math.sqrt(sum(x*x for x in grad))>GRAD_EPS:
            direction=unit(grad)
            qdot=tuple(d-beta*s for d,s in zip(qdot,direction))
    return unit(tuple(p+d*dt for p,d in zip(q,qdot)))


def euler(q):
    w,x,y,z=unit(q)
    return tuple(math.degrees(v) for v in (
        math.atan2(2*(w*x+y*z),1-2*(x*x+y*y)),
        math.asin(max(-1.0,min(1.0,2*(w*y-z*x)))),
        math.atan2(2*(w*z+x*y),1-2*(y*y+z*z))))


def from_euler(roll,pitch,yaw):
    r,p,y=(math.radians(a)/2 for a in (roll,pitch,yaw))
    cr,sr=math.cos(r),math.sin(r);cp,sp=math.cos(p),math.sin(p);cy,sy=math.cos(y),math.sin(y)
    return (cr*cp*cy+sr*sp*sy,sr*cp*cy-cr*sp*sy,cr*sp*cy+sr*cp*sy,cr*cp*sy-sr*sp*cy)

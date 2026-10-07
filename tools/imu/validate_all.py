"""One entry point for all reproducible IMU checks."""
from pathlib import Path
import subprocess
import sys


def main():
    here=Path(__file__).resolve().parent
    for script in ('validate_upstream.py','validate.py','validate_euler.py','validate_math.py','validate_demo.py'):
        print(f'Running {script}',flush=True)
        subprocess.run([sys.executable,str(here/script)],check=True)


if __name__=='__main__':main()

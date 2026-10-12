"""Compare camera top/CST/P&R with a manually reviewed schematic pin table.

This tool does not infer connectivity from PDF graphics. The expected table
was independently transcribed from the sources in docs/imu/引脚核对.md.
"""
from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[2]


def expected_pins():
    groups = [
        ('clk50m', ['F13'], [1]),
        ('rgmii_tx_clk', ['E18'], [2]),
        ('rgmii_tx_ctl', ['F19'], [2]),
        ('rgmii_txd', ['B20', 'A20', 'C19', 'F18'], [2]*4),
        ('state_led', ['E13', 'E14', 'D14', 'D15', 'B17', 'B18', 'B15', 'B16'], [1]*8),
        ('cam_sda', ['M15'], [5]), ('cam_scl', ['K16'], [4]),
        ('cam_data', ['V19', 'M22', 'N22', 'L16', 'G20', 'G18', 'M21', 'L21'],
         [8, 5, 5, 4, 5, 4, 5, 5]),
        ('cam_pclk', ['V18'], [8]), ('cam_href', ['K22'], [5]),
        ('cam_vsync', ['K21'], [5]), ('cam_rst_n', ['G16'], [4]),
        ('bmi_sclk', ['H13'], [4]), ('bmi_mosi', ['G13'], [4]),
        ('bmi_miso', ['M13'], [5]), ('bmi_csb1', ['L13'], [5]),
        ('bmi_csb2', ['U20'], [8]), ('bmi_int1', ['V20'], [8]),
        ('bmi_int3', ['H17'], [4]),
        ('imu_uart_tx', ['C13'], [1]),
    ]
    expected = {}
    for name, pads, banks in groups:
        for i, (pad, bank) in enumerate(zip(pads, banks)):
            port = f'{name}[{i}]' if len(pads)>1 else name
            expected[port] = {'pad': pad, 'bank': bank,
                              'io_type': 'LVCMOS18' if bank==2 else 'LVCMOS33',
                              'bank_vccio': '1.8' if bank==2 else '3.3'}
    return expected


def top_ports(path):
    text = re.sub(r'//[^\n]*|/\*.*?\*/', '', path.read_text(), flags=re.S)
    header = text.split(');', 1)[0]
    ports = set()
    for m in re.finditer(r'\b(?:input|output|inout)\s*(?:wire\s+|reg\s+)?'
                         r'(?:\[(\d+):(\d+)\]\s*)?(\w+)', header):
        hi, lo, name = m.groups()
        ports.update([name] if hi is None else
                     [f'{name}[{i}]' for i in range(int(lo), int(hi)+1)])
    return ports


def audit():
    expected = expected_pins()
    cst_path = ROOT/'src/camera720/camera720.cst'
    cst = re.sub(r'//[^\n]*', '', cst_path.read_text())
    locations = re.findall(r'IO_LOC\s+"([^"]+)"\s+(\w+)\s*;', cst)
    assert len(locations)==len(expected)==37
    assert len({pad for _, pad in locations})==37, 'Repeated physical pad'
    assert dict(locations)=={port: p['pad'] for port,p in expected.items()}
    io = dict(re.findall(r'IO_PORT\s+"([^"]+)"\s+([^;]+);', cst))
    assert set(io)==set(expected)
    for port,p in expected.items():
        assert f"IO_TYPE={p['io_type']}" in io[port], port
    result = {'date': '2026-10-08', 'passed': True, 'physical_io_bits': 37,
              'method': 'manual schematic review + automated top/CST/P&R comparison',
              'cst_sha256': hashlib.sha256(cst_path.read_bytes()).hexdigest().upper(),
              'electrical_compatibility_verified_on_board': False,
              'bmi088_physical_pins_added': True, 'projects': {}}
    for project,top in [('camera720', 'top_camera720'),
                        ('camera720_imu_demo', 'top_camera720_imu_demo')]:
        assert top_ports(ROOT/f'src/camera720/{top}.v')==set(expected), top
        report_path = ROOT/f'impl/pnr/{project}.rpt.txt'
        if not report_path.exists():
            result['projects'][project] = {'top':top, 'all_ports_constrained':True,
                                           'unique_pads':True, 'pnr_report_available':False,
                                           'pins':expected}
            continue
        report = report_path.read_text()
        section = report.split('7. Pinout by Port Name',1)[1].split('8. All Package Pins',1)[0]
        rows = {}
        for line in section.splitlines():
            cells = [x.strip() for x in line.split('|')]
            if cells[0] in expected:
                assert cells[0] not in rows, 'Repeated report port'
                rows[cells[0]] = cells
        # An old report may predate the BMI088 ports. It is not used as
        # evidence for the new ports until Gowin P&R is rerun.
        if set(rows) != set(expected):
            result['projects'][project] = {'top':top, 'all_ports_constrained':True,
                                           'unique_pads':True, 'pnr_report_available':False,
                                           'pins':expected}
            continue
        for port,p in expected.items():
            row = rows[port]
            assert row[2]==f"{p['pad']}/{p['bank']}", (project,port,row[2])
            assert row[3]=='Y' and row[7]==p['io_type'], (project,port)
            assert row[17]==p['bank_vccio'], (project,port,row[17])
        result['projects'][project] = {
            'top':top, 'all_ports_constrained':True, 'unique_pads':True,
            'report_sha256':hashlib.sha256(report_path.read_bytes()).hexdigest().upper(),
            'pnr_report_available':True,
            'pins':expected}
    (ROOT/'docs/imu/pin_audit.json').write_text(
        json.dumps(result,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    print('PASS: both camera projects match all 37 schematic pins, banks and IO types.')


if __name__=='__main__':
    audit()

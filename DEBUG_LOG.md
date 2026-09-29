# FPGA DDR / USB Debug Log

This log tracks changes, build results, board observations, and what each test
does or does not establish. The DDR is not considered validated until
`CAL=1` and a captured frame passes the host-side checksum.

## 2026-09-28: USB_Debug frame capture added

- Change: Added a 115200-baud UART transmitter and a 64x64 RGB565 crop of the
  framebuffer readback. Added `tools/capture_debug_frame.py` to receive the
  ASCII frame, verify its checksum, and save a PNG. UART TX is constrained to
  C13, the FPGA CH340E transmit route.
- Verification: RTL simulation passed with 4096 pixels, 64 rows, and the
  expected frame trailer/checksum. Gowin synthesis and place-and-route
  completed; the pin report placed `uart_tx` at C13, LVCMOS33.
- Board feedback: The host received repeated `CAL=0 COUNT=0000` lines.
- What this established: USB_Debug wiring, COM port selection, UART settings,
  and status transmission work. DDR calibration had not completed, so the
  capture logic correctly did not send a framebuffer image.
- Limitation: The original status did not distinguish PLL lock, DDR reset, or
  the DDR clock-control request.

## 2026-09-28: PLL and DDR status instrumentation

- Change: Changed the top-level PLL instance from `Gowin_PLL_MOD` to the
  generated `Gowin_PLL` wrapper and connected its `mdclk` to the 50 MHz board
  clock. Added UART fields `PLL`, `RSTN`, `STOP`, and `DRST`; mapped these raw
  status levels to LEDs D2-D5. Added `tools/build_debug.tcl` to build the saved
  `gowin.gprj` project reproducibly.
- Verification: UART simulation passed with the longer diagnostic status and
  the complete image payload. Gowin synthesis and place-and-route completed.
  The diagnostic bitstream was generated at
  `impl/pnr/gowin.fs` on 2026-09-28 13:01:34. The pin report still maps UART TX
  to C13.
- Timing result: The same build reports worst listed DDR PHY setup slack of
  approximately -4.143 ns. A generated bitstream is therefore not evidence
  that DDR timing is met.
- Board feedback (2026-09-29, user report from COM14):

  ```text
  CAL=0 COUNT=0000 PLL=1 RSTN=1 STOP=1 DRST=0
  ```

- What this established: The PLL reports locked; the external DDR RESET_N is
  deasserted; the DDR controller's internal reset output is low. Calibration
  still does not complete. This narrows the fault beyond basic UART, PLL-lock,
  and reset-release checks, but does not prove that the 400 MHz clock reaches
  the memory or that PHY training succeeds.
- `STOP` interpretation: The Gowin DDR3 examples found locally connect the
  DDR IP's `pll_stop` output to PLL `enclk2`. Thus `STOP=1` is a clock-enable
  request in that reference design, not a standalone DDR error code. The
  current generated PLLA wrapper has no `enclk2` port and statically enables
  CLKOUT2 (`CLKOUT2_EN=TRUE`); it does not currently apply the request as a
  dynamic gate. Do not invert or otherwise change `STOP` based only on its
  name.

## 2026-09-29: DDR_A14 left undriven (candidate fix)

- Evidence: The board schematic routes DDR_A14 to FPGA ball L3. The existing
  PnR pin report showed L3 as an unassigned input with pull-up, while
  `DDR3MI.v` exposes only `O_ddr_addr[13:0]`; the generated geometry is
  `ROW_WIDTH=14`, `COL_WIDTH=10`, `DQ_WIDTH=32`, `DRAM_WIDTH=16`.
- Memory datasheet check: MT41K128M16 uses row A[13:0] and column A[9:0]
  for x16 organization. A14 is nevertheless an address-bus pin used in the
  mode-register address definitions, so it must not be left electrically
  floating. The prior PnR report's weak input pull-up is not a controlled
  controller output.
- Change: Expanded only the board-level address port to 15 pins, kept the
  generated DDR IP geometry unchanged, connected A[13:0] to the IP, and drove
  A14 low at FPGA L3. Added an SSTL135_I constraint for this 1.35 V DDR bank.
- Build result: Gowin synthesis and place-and-route completed on 2026-09-29.
  `impl/pnr/gowin.fs` was generated at 19:09:33. The new pin report confirms
  `ddr_addr[14]` is an output at L3/Bank 10 using SSTL135_I, 1.35 V. UART
  frame simulation still passes. The listed worst DDR PHY setup slack remains
  -4.143 ns.
- Status: This is a controlled hardware hypothesis, not yet board-validated.
  If calibration changes to `CAL=1`, the undriven A14 was causal or
  contributory; if not, the DDR PHY calibration stage still needs further
  instrumentation.

## Current state and next experiment

1. Keep the current diagnostic bitstream loaded. Use PuTTY on COM14 at
   115200, 8-N-1, no flow control. A single complete status line is enough;
   the Python frame-capture script will wait indefinitely while `CAL=0`.
2. Program the new `impl/pnr/gowin.fs` generated at 19:09:33 and cold-power-
   cycle the board. Do not use the earlier 13:01 bitstream.
3. Open PuTTY on COM14 at 115200, 8-N-1, no flow control. `CAL=1` is the
   expected improvement. If it remains `CAL=0`, record the entire status line,
   then verify 400 MHz differential CK at an appropriate test point with a
   suitable probe. Do not probe a BGA pin directly or attach an ordinary
   grounded oscilloscope probe across the pair.
4. If CK is present at the expected rate but calibration remains low, enable
   DDR IP debug ports or use the Gowin on-chip logic analyzer to inspect the
   calibration stage and DQS lanes. Do not change geometry or timings
   speculatively.
5. Once `CAL=1` appears, run
   `python tools/capture_debug_frame.py COM14` with PuTTY closed. Expected
   result: a complete frame, matching checksum, and `debug_frame.png`.

## 2026-09-29: Board feedback after A14 candidate

- User-reported UART output remains:

  ```text
  CAL=0 COUNT=0000 PLL=1 RSTN=1 STOP=1 DRST=0
  ```

- User-reported LEDs: D7 is blinking; D6, D5, D1, and D0 appear steadily on;
  D3 has a faint blink. D2 and D4 were not specified.
- Interpretation: UART confirms the A14 candidate has not made DDR calibration
  complete (`CAL=0`, `COUNT=0000`). It does not establish that the A14 change
  was actually programmed unless the loaded image is confirmed as the
  `impl/pnr/gowin.fs` built at 19:09:33. The LED observations do not cleanly
  match the raw UART status (for example UART reports stable `RSTN=1`, while
  D3 appears to flicker), so do not infer reset state or LED polarity from the
  current visual report. UART is the authoritative readout for these signals.
- Usefulness: This is a valid repeat observation that calibration remains
  stuck, but it does not identify which DDR PHY training stage or physical
  signal is failing. Re-running the frame capture is not useful until
  `CAL=1`; it will wait because no valid frame is available.
- Next action: Confirm the programmed bitstream timestamp/path. If it is the
  19:09:33 image, stop repeating the same programming/capture test. Next
  instrument the DDR PHY calibration/debug status (the current IP configuration
  has `DEBUG_PORT_ENABLE=false`) or verify the differential DDR clock with
  suitable equipment and an appropriate test point. Do not change DDR geometry
  or timing parameters speculatively.

## 2026-09-29: Repeat test and debug-port investigation

- Board feedback after the user followed the reprogram/cold-start instructions:
  UART still reports `CAL=0 COUNT=0000 PLL=1 RSTN=1 STOP=1 DRST=0`. The exact
  programmed file was not stated in this report, so correlate it with the
  19:09:33 image before treating A14 as fully tested.
- Investigation: `src/DDR3MI/DDR3MI.ipc` has `DEBUG_PORT_ENABLE=false`, and the
  generated `src/DDR3MI/DDR3MI.v` interface has no PHY debug outputs. The local
  Gowin V1.9.12.03 installation contains the matching 1:4 high-speed DDR3
  `DDR3_TOP.v` template with optional `dbg_vector1_out` through
  `dbg_vector4_out`. At the current 32-bit DQ / four-DQS-lane organization,
  these buses are 8, 16, 12, and 32 bits respectively. The source template
  forwards them from the PHY; exact bit meanings must be taken from the
  regenerated IP/version documentation and must not be guessed from names.
- Conclusion: More useful internal PHY telemetry is available, but turning the
  IPC flag on alone is insufficient. Regenerate the DDR IP in Gowin IP Core
  Generator, verify that the generated `DDR3MI` template/interface now exposes
  all four vectors, then wire them into a UART diagnostic packet. Keep the
  current bitstream and generated IP files as the known rollback point.
- Next expected test: one status record containing existing reset/lock fields
  plus all four debug vectors in hex. Compare snapshots after cold start and
  observe whether training vectors change or remain stuck; only then decide
  whether to investigate reset/clock, DQS lane routing, or PHY timing. A UART
  snapshot still cannot prove the physical 400 MHz differential CK waveform.

## 2026-09-29: DDR3 IP dialog settings reviewed

- The supplied screenshots show the intended GW5AT-LV60PG484AC1/I0 DDR3
  component configuration. Keep the existing 400 MHz, 1:4 ratio, DQ width 32,
  DRAM width 16, rank 1, bank 3, row 14, column 10, and the existing controller
  interface/buffer settings unchanged for this diagnostic rebuild.
- In Debug Setting, enable only `Debug Port Enable`; leave `Debug Parameter
  Enable` unchecked and do not alter the four debug parameter values.
- Important integration detail: the dialog currently names the output `DDR3_d`
  in `src/DDR3_d`, while the project instantiates module `DDR3MI` from
  `src/DDR3MI`. A generated `DDR3_d` core will not be used by the current top
  unless it is explicitly integrated. Back up the project before regenerating
  over `DDR3MI`, or generate separately and later integrate the new module and
  debug ports deliberately.
- No IP configuration, RTL, or bitstream was changed as part of reviewing the
  screenshots; wait for generated port-template confirmation before editing
  UART telemetry.

## 2026-09-29: DDR3_d PHY telemetry integrated

- Generated IP confirmation: `src/DDR3_d/DDR3_d.ipc` has
  `DEBUG_PORT_ENABLE=true`; its generated wrapper exposes four outputs:
  `dbg_vector1_out[7:0]`, `dbg_vector2_out[15:0]`,
  `dbg_vector3_out[11:0]`, and `dbg_vector4_out[31:0]`. Its clock, width, rank,
  row, and column settings match the existing DDR3MI configuration. The project
  includes the new module, but previously the top still instantiated DDR3MI.
- RTL change: top now instantiates `DDR3_d` and wires all four vectors into the
  USB UART status reporter. The UART appends `DBG1`, `DBG2`, `DBG3`, and `DBG4`
  as 2/4/3/8 hex digits once per second while calibration is incomplete. The
  vectors are sampled through two stages into the UART/video clock domain;
  they are diagnostic snapshots, not a coherent high-speed waveform capture.
- Signal clues from generated netlist: DBG1 is the shared DLL step;
  DBG3 contains four 3-bit read-clock selections; DBG4 contains four 8-bit
  write-step values. DBG2 contains four per-lane read-calibration values. Treat
  DBG2 as raw hex until the vendor defines its exact encoding.
- Test discovery/fix: widening the status line exposed that `char_index` was
  only 6 bits, so it wrapped before the new 86-character status line ended.
  Widened it to 7 bits. UART simulation now passes with all four known debug
  patterns and a complete 4096-pixel frame (16,628 received UART bytes and
  checksum check passed).
- Build: Gowin V1.9.12.03 synthesis, place-and-route, and bitstream generation
  completed. Current `impl/pnr/gowin.fs` timestamp is 2026-09-29 19:50:24;
  UART remains at C13 and DDR_A14 remains at L3, SSTL135_I. Existing warnings
  include generic clock routing (`clk_d`) and a determined DDR `fclkdiv` clock
  that was not created. Worst reported DDR PHY setup slack is about -4.176 ns
  (previous build about -4.143 ns); timing is not closed.
- Board status: not yet tested with this debug-enabled bitstream. The root
  cause of `CAL=0` remains unknown until the four DBG fields are observed on
  hardware. Build completion must not be described as DDR success.
- Board test procedure: program the exact current `impl/pnr/gowin.fs`, cold
  power-cycle, open COM14 at 115200 8-N-1/no flow control, and send at least
  five complete status lines. Expected line suffix:
  `DBG1=XX DBG2=XXXX DBG3=XXX DBG4=XXXXXXXX`. Keep PuTTY open only for these
  lines and do not run frame capture while `CAL=0`.

## 2026-09-29: First DDR PHY debug-port board capture

- User captured 12 successive status lines. Stable fields remain
  `CAL=0 COUNT=0000 PLL=1 RSTN=1 STOP=1 DRST=0`; the debug values vary:
  `DBG1=30`, DBG2 runs through `4444,9999,1111,5555,AAAA,2222,7777,BBCC,
  3444,8888,0000,5555`; DBG3 also changes on every record; DBG4 is mostly
  `1D212B27` / `1E212B27` with occasional lane-step changes.
- Interpretation supported by the generated netlist: the PHY debug logic is
  clocking and updating its calibration-related outputs; this is not a
  completely static controller state. DBG3 is four per-lane 3-bit RCLKSEL
  fields; DBG4 is four per-lane 8-bit WSTEP fields; DBG1 is the shared DLL
  STEP feedback. DBG2 tracks the per-lane read-calibration `read_i` values.
  Its exact code semantics are not documented in the generated wrapper, so
  retain it as raw hex.
- What this does not prove: changing debug values alone do not prove successful
  DQ/DQS sampling, a valid DDR clock at the DRAM, or why calibration does not
  assert done. The lane settings in DBG4 look mostly stable across these
  samples while read-selection/data-related values move, but this is a clue,
  not a definitive read-eye failure diagnosis.
- Next experiment: keep this image loaded and collect a timestamped 60-second
  UART log from a cold power-on. Note when the first line appears and whether
  `CAL` ever becomes 1. If vectors continue changing for the whole interval
  while CAL stays low, report that as a continuing calibration/search failure;
  do not re-run frame capture. If DBG values stop changing, preserve the final
  values and elapsed time. In either case, compare against a controlled CK
  waveform check at a suitable DDR test point before changing memory timings.

## 2026-09-29: Extended UART log parsed

- Attachment contains 93 status records, all with `CAL=0 COUNT=0000`; at the
  one-record-per-second reporting cadence this is roughly 90 seconds of
  unsuccessful initialization (the pasted file has no timestamps, so elapsed
  time is approximate).
- PuTTY/copy formatting inserted spaces inside DBG4 on most lines. Removing
  whitespace after `DBG4=` reconstructs exactly eight hex digits on all 93
  records; this is a presentation artifact and not evidence of truncated RTL
  output.
- Lane decode of DBG3 (`RCLKSEL`, three bits per lane) shows that each of the
  four lanes visited all values 0 through 7 during the capture. DBG4 (`WSTEP`,
  eight bits per lane) stayed near lane-specific values: lane0 mostly 27/28,
  lane1 2A/2B/2C, lane2 20/21, lane3 1D/1E. DBG1 remained 30. DBG2 continued
  changing and is retained as raw read-calibration data.
- Current leading diagnosis: the PHY's read-side phase/eye training is
  repeatedly sweeping all RCLKSEL choices but never reaches calibration done.
  This is substantially more specific than a static reset/clock-enable failure,
  but does not identify whether the cause is missing/poor DQ-DQS readback,
  physical routing/signal integrity, or a configuration/clock issue. Do not
  change timing values based on this alone.
- Next checks: first confirm at a suitable DDR test point that differential CK
  is present and has the expected frequency/levels. Then inspect board schematic
  and continuity/pin mapping for all four DQS pairs and their associated DQ
  groups, followed by the generated IP's mode/drive/termination settings. Keep
  the debug image and exact full raw UART capture for comparison; do not use a
  terminal copy that wraps long lines if lane values are being analyzed.

## 2026-09-29: Existing board data sufficiency and reference-project value

- The available ACG138 core-board schematic identifies two DDR3L devices,
  `MT41K128M16T-125`, each x16, forming the FPGA's 32-bit DDR bus. The current
  DDR IP configuration (`DQ_WIDTH=32`, `DRAM_WIDTH=16`, one rank, 14 row bits,
  10 column bits, 400 MHz, 1:4) is structurally consistent with that topology.
  This makes a gross width/geometry mismatch less likely, but does not validate
  every timing, mode-register, electrical, or board-routing detail.
- The project has substantial static data already: exact FPGA target/package
  in the project/IP, memory part number in the schematic, board-to-FPGA pin
  constraints, DDR IP generation artifacts, PnR timing report, and read-PHY
  debug snapshots. The missing evidence is chiefly a known-good reference for
  this board/revision and direct electrical confirmation of CK/DQS/voltage,
  not simply more generic device documentation.
- Other GW5AT-60 reference projects are useful when they include the same
  silicon family/package and preferably the same DDR IP/tool version and
  comparable DDR3 device/topology. Compare their `.ipc`, generated parameter
  files, reset/PLL hookup, memory initialization/timing configuration, and
  timing constraints. A different board's pin constraints, bitstream, or raw
  DDR layout must not be copied as-is; DDR pinout and signal routing are
  board-specific.
- Next step is to obtain any working GW5AT-60 DDR3 example with its project,
  IP config, constraints, and reports, then make a parameter/clock/reset
  comparison table before changing this design. In parallel, verify physical
  DDR CK if suitable probing is available. The present evidence points to a
  repeatedly scanning read-side PHY calibration that does not converge, but
  does not yet distinguish configuration, pin mapping, clock/electrical, or
  signal-integrity causes.

## 2026-09-29: Multi-functional-Protocol-Debugger ACG720 source reviewed

- README claims an ACG720 system with `MT41K128M16JT` DDR3. The available
  physical constraints (`M1_SC_MCU_LCD.cst`, `fpga_project_1.cst`, and
  `FX2_CDC_USB.cst`) identify the target as
  `GW5AT-LV138PG484AC1/I0` / GW5AT-138, not this project's GW5AT-LV60. The
  DDR constraints use 1.5 V SSTL15/SSTL15D and its shown RTL interface is
  16-bit DQ with two DQS lanes, unlike ACG138's 32-bit bus, four DQS lanes,
  and 1.35 V DDR3L signaling.
- Although `acm2108.v` contains a 16-bit DDR-shaped port and a call to
  `ddr3_ctrl_2port`, that module and a corresponding DDR IP `.ipc`/generated
  wrapper are absent from the repository. This file explicitly labels the
  current revision "不接 DDR3" and says it bypasses DDR in favor of BRAM.
  Therefore the README alone is not proof that this checked-in revision has a
  working DDR implementation; the repository is not a known-good DDR baseline.
- Safe value: the code gives a possible architectural example for a separate
  200 MHz DDR reference clock and reset/lock wiring, but its missing controller
  implementation prevents validation. Do not copy its clock frequency,
  constraints, IO standards, or pin assignments into ACG138 without the actual
  DDR IP and board schematic. The DDR IP's `MEMORY_CLK` meaning must be checked
  rather than inferred from comments such as `clk_400m`.
- Manuals reviewed: DS981 states GW5AT-60 supports DDR3 up to 1333 Mbps and
  lists SSTL135 / SSTL135D 1.35 V IO standards; UG983 contains the GW5AT-60
  PG484A package pinout. These establish FPGA capability/package pin functions,
  not the ACG138 board's PCB routing or the DDR memory's complete timing/mode
  requirements.
- Implication: current evidence does not point to lack of FPGA product data as
  the primary blocker. The valuable missing reference is a complete, proven
  DDR project (controller IP/configuration, matching PLL/reset, board-specific
  constraints and successful calibration/build evidence) or electrical CK/DQS
  measurements from this specific board.

The current UART/status test is useful: it isolated the problem to DDR
initialization or the DDR physical/PHY path. It has not yet identified the
specific failing DDR signal or calibration stage.

## 2026-09-29: DDR PLL stop-control loop and reset synchronization

- Root-cause candidate addressed: the previous top-level observed the DDR IP's
  active-low `pll_stop` output but did not use it to control `memory_clk`.
  IPUG281 section 4.4.4 requires GW5A(S)(T) devices without a PLL `ENCLK`
  input to route `pll_stop` through `pll_mDRP_intf` into the PLL mDRP port.
- The first attempted implementation used a normal PLL with an `ENCLK2` port.
  Gowin PnR rejected it with `ERROR (RP0008): There is no PLL resource in
  current device`, confirming that this LV60 PLLA cannot use that connection.
  That attempt was removed.
- The working implementation now uses the LV60 `ddr_pll`, `ddr_pll_MOD`, and
  `pll_mDRP_intf` sources from the local `ch38_uart_ddr3_tft_hdmi` reference.
  `pll_stop` edges generate the adapter `wr` pulse. `PLL_INIT` owns mDRP during
  PLL startup; after its synchronized lock output asserts,
  `pll_init_bypass` switches mDRP ownership to the stop-control adapter.
  The DDR IP receives this PLL's real LOCK output and its 400 MHz `clkout2`.
- Added an asynchronous-assert, two-cycle synchronous-release reset in the
  DDR IP's 50 MHz `clk` domain. The synchronized reset now drives both the DDR
  IP and the mDRP adapter, matching IPUG281's reset-interface requirement.
- UART status now includes cumulative evidence that short clock/reset events
  occurred between the one-second text reports:
  `SLOW` (ever saw `pll_stop=0`), `SE` (`pll_stop` edge count), `PD` (PLL lock
  falling-edge count), and `RE` (DDR internal reset edge count). Counters
  saturate at `FF` and reset only with the board reset.
- Final build with Gowin V1.9.12.03 completed synthesis, placement, routing,
  timing analysis, and bitstream generation at 2026-09-29 22:24:26. The mDRP
  adapter was compiled and was not reported as swept. Resource report shows
  two PLLA resources used (`2/8`). Output:
  `impl/pnr/gowin.fs`, 19,479,211 bytes, SHA-256
  `FD9B990AABEC660E9D40EAA60850E9E5155E9970609193FD9159E33AD7EC4F64`.
- Remaining PnR warnings are `TA1132` for an uncreated internal DDR PHY
  `CLKDIV` generated clock and `PR1014` for internal `clk_d` using generic
  routing under its constraint. Timing reports also contain expected-looking
  asynchronous FIFO/debug-crossing failures and DDR training paths. These
  need later constraint/timing cleanup, but they do not prevent this targeted
  hardware experiment from determining whether the missing `pll_stop` loop
  blocked calibration.

### Hardware test for this image

1. Program the newly generated `impl/pnr/gowin.fs`; verify its timestamp is
   2026-09-29 22:24:23 (or use the SHA-256 above to avoid loading an old file).
2. Completely remove board power for several seconds, power it again, and run
   `python .\tools\capture_debug_frame.py COM14` at 115200 8-N-1.
3. Capture at least the first 20 complete status lines, including the first
   line immediately after power-up if possible. Do not use PuTTY at the same
   time because only one process may own COM14.
4. Success is `CAL=1`; the script should then receive `FRAME 64 64 RGB565`
   and write the reconstructed crop image. `COUNT=1000` means all 4096 pixels
   were captured.
5. If `CAL=0`, interpret the cumulative fields before changing parameters:
   `SLOW=1` or `SE>00` proves the DDR IP requested at least one memory-clock
   stop transition; `PD>00` means the new mDRP operation caused or coincided
   with PLL lock loss; `RE>00` proves the DDR internal reset changed state.
   If `SLOW=0 SE=00`, the PHY did not request a low pulse during the observed
   boot, or the pulse was not observed in the debug clock domain. Return the
   complete lines together with the LED state for the next diagnosis.

### 2026-09-29 hardware result: DDR calibration succeeded

- After programming the 22:24:23 image and power-cycling, UART reported:
  `CAL=1 COUNT=1000 PLL=1 RSTN=1 STOP=1 DRST=0 DBG1=30 DBG2=6666`
  `DBG3=FFF DBG4=20242E2A SLOW=1 SE=03 PD=00 RE=02`.
- `CAL=1` proves that the DDR PHY completed hardware calibration. `SLOW=1`
  and `SE=03` confirm that the DDR IP requested memory-clock stop transitions
  and the newly connected control path observed them. `PD=00` confirms the
  DDR PLL did not lose lock. `RE=02` is consistent with the DDR internal reset
  entering and leaving its startup state.
- The PC tool received all 4096 pixels (`COUNT=0x1000`), validated checksum
  `58C0`, and saved `debug_frame.png`. This proves the tested path can write
  through the frame-buffer interface, read data back, serialize it over UART,
  and reconstruct a stable image on the PC.
- The recovered crop is not yet the exact expected geometry. Mode `000` in
  `testpattern.v` generates eight vertical color bars. A crop spanning
  x=608..671 should cross the x=640 boundary and therefore appear as a
  left/right green-to-magenta split. The observed image instead contains
  horizontal green/yellow/red/black/white bands. DDR calibration is solved,
  but frame-buffer line stride, address ordering, producer/consumer geometry,
  and synchronization must be checked before declaring the full video path
  pixel-accurate.

## 2026-09-29: Two additional DDR3 reference projects reviewed

- `C:\Users\HP\Desktop\gowin\gowin\ddr3_ctrl` has a project file targeting
  GW5AT-LV60PG484AC1/I0 and a generated DDR3 controller with a 16-bit DQ bus
  (`gwmc_param.v`: DQ_WIDTH=16, DRAM_WIDTH=8, 14 row bits, 10 column bits,
  one rank, 400 MHz, 1:4). This is useful for controller/PLL/adapter RTL
  patterns, but its interface is half the width of this ACG138 board's 32-bit
  DDR bus and it has no board-specific `.cst` in the supplied project.
- Do not treat `ddr3_ctrl`'s stored PnR report as a successful LV60 result:
  the report identifies GW5AT-LV138PG484AC1/I0, Gowin 1.9.10.03, and records
  repeated PR1085 IOLOGIC/Bank_VCCIO placement errors. The synthesis log says
  synthesis finished, which proves only synthesis, not successful place and
  route or DDR calibration.
- `C:\Users\HP\Desktop\gowin\gowin\ch38_uart_ddr3_tft_hdmi` has a project
  file and generated DDR/PLL IP targeting GW5AT-LV60PG484AC1/I0. Its generated
  DDR parameters are likewise 16-bit DQ / x8 DRAM, one rank, 14-row/10-column,
  400 MHz and 1:4. Its top-level uses a 50 MHz input and a dedicated PLL output
  as the DDR `memory_clk`; the DDR PLL config is nominally 400 MHz. This is the
  closer reference for the current project's 400 MHz clock and reset/`pll_stop`
  hookup, but its memory topology is not the board's 32-bit bus.
- Critical constraint mismatch: the second project's `.gprj` selects LV60,
  while `src/uart_ddr3_tft_hdmi.cst` header says LV138 and constrains DDR IO as
  SSTL15/SSTL15D with BANK_VCCIO=1.5 V. The ACG138 board DDR3L is 1.35 V and
  the GW5AT-60 design must be checked against its own schematic/pin map and
  SSTL135-capable bank assignment. Never copy those pin locations or 1.5 V
  settings into this project. The project has a synthesis log ending in
  `GowinSynthesis finish` and an `ao_0.fs` bitstream, but the supplied folder
  lacks a matching PnR log/report tying that output to a successful LV60 build;
  neither artifact proves the DDR trained on hardware.
- The second project's synthesis log has additional RTL warnings (including
  unconnected `rd_load`/`wr_load`, width truncations, and `burst` width
  mismatch). These affect confidence in its memory traffic test, but are not by
  themselves evidence for why its DDR PHY calibration succeeds or fails.
- Conclusion: `ch38_uart_ddr3_tft_hdmi` is worth using as a parameter/clock/
  reset comparison source; `ddr3_ctrl` is useful only for RTL structure and
  exposes an unsuccessful/stale LV138 PnR attempt. Neither is a known-good
  board-matched 32-bit DDR3L calibration reference. Keep the current 32-bit
  ACG138 project unchanged until comparing the actual DDR pin groups/voltages
  with the board schematic and verifying DDR CK electrically.

## 2026-09-29: OV5640 DDR3 HDMI reference reviewed

- `D:\HP\ch47_ov5640_ddr3_hdmi` project and generated DDR/PLL IP target
  GW5AT-LV60PG484AC1/I0. The DDR IP's generated parameters are DQ_WIDTH=16,
  DRAM_WIDTH=8, one rank, 14 row bits, 10 column bits, 400 MHz, and 1:4. The
  top-level uses a 50 MHz input and routes the DDR PLL's output to the DDR
  interface; its signal is called `loc_clk400m` but passed through a port named
  `clk_200m`, so the connected signal/configuration (400 MHz) matters more
  than the stale port/comment naming. This is a similar 16-bit reference, not
  a match for ACG138's 32-bit DDR3L topology.
- The project's `.gprj` says LV60, but `src/ov5640_ddr3_hdmi.cst` header says
  LV138 and the DDR pins are constrained as SSTL15/SSTL15D at 1.5 V. Do not
  copy those pin assignments or IO voltage settings to ACG138. This is the
  same board-constraint mismatch seen in `ch38_uart_ddr3_tft_hdmi`.
- It contains a synthesis log ending in `GowinSynthesis finish` and an
  `impl/pnr/ov5640_ddr3_hdmi.fs` bitstream of matching timestamp. This suggests
  a bitstream was generated, but the supplied folder has no corresponding PnR
  log/report to establish the exact device/constraint result, and no hardware
  calibration evidence. A generated bitstream alone does not establish that
  DDR initialization completed on the board.
- The controller hookup is structurally useful for studying a sensor-to-FIFO-
  to-DDR-to-display data path and the DDR PLL/`pll_stop` logic. The build log
  also warns that `burst` is 32 bits at the instance but 1 bit at the IP port;
  FIFO adapter address arithmetic has 29-to-28-bit truncation warnings. Those
  warnings merit cleanup before trusting its sustained image traffic, though
  they do not alone explain PHY calibration.
- Conclusion: this is a useful integrated RTL example for the planned OV5640
  data path, but not a validated board-matched DDR3L reference. It does not
  provide new evidence that the present ACG138 calibration failure is caused
  by RTL versus pins, voltage, clock, or signal integrity. Continue using the
  ACG138 schematic and direct CK/DQS checks as the ground truth.

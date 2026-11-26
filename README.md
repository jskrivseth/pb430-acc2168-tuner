# pb430-acc2168-tuner (`ACCTUNE.COM`)

A tiny (2,585-byte) pure 16-bit MS-DOS opt-in chipset and onboard Cirrus Logic VGA tuner for **ACC Micro 2046 / 2168 / 2168GT** 486 motherboards, developed and real-hardware tested on a **Packard Bell PB430** (Legend Elite 2038).

Running `ACCTUNE` with **no arguments** is completely **read-only**: it prints the live ACC2168 register values (`04h`, `05h`, `0Bh`, `18h`, `19h`), decoded state, and usage help without modifying hardware (and without touching VGA ports unless a Cirrus VGA flag is requested). Every tweak is strictly opt-in, combinable, and reversible.

## Usage

```text
ACCTUNE                     Read-only ACC register status + help (no writes)
ACCTUNE /PW+  | /PW-        Posted Write ON/OFF (04h b7)
ACCTUNE /R2|/R4|/R8|/R16    DRAM Refresh divisor (05h b1:0; /R=/R4, /R-=/R2)
ACCTUNE /BR1..8 | /BR-      Burst Refresh ON (1-8 rows, /BR=4) / OFF (18h b1, 19h b2:0)
ACCTUNE /AT-  | /AT+        AT Bus Refresh OFF/ON (18h b0: 1=disabled, 0=stock)
ACCTUNE /W0+  | /W0-        486 0-WS Mem Write ON/OFF (04h b6)
ACCTUNE /C1+  | /C1-        1T/2T CAS Write pulse (0Bh b1:0: 00=1T, 01=2T; experimental)
ACCTUNE /P0+  | /P0-        0-WS/1-WS Posted Write (18h b4; experimental)
ACCTUNE /V                  Read-only Cirrus CL-GD542x VGA status (/VGA)
ACCTUNE /VIO+ | /VIO-       Cirrus VLB 1T/2T I/O RDY# (SR16 b7:6)
ACCTUNE /VM50..64 | /VM-    Cirrus MCLK MHz (50/54/55/57/59/61/63/64; /VM=54, /VM-=50)
ACCTUNE /OFF                Reset ACC tuned bits back to safe stock (also /STOCK, /0)
```

- Flags are **case-insensitive**, accept `/` or `-`, and **omit `+` as shorthand to enable** (e.g. `ACCTUNE /PW /R8 /BR4 /AT- /VIO /VM57`; `/R` = `/R4`, `/BR` = `/BR4`, `/VM` = `/VM54`).
- Flags are **combinable** in one command (e.g. `ACCTUNE /PW /R8 /BR4 /AT- /VIO /VM57`, `ACCTUNE /PW- /R4`).
- Only registers explicitly referenced by your flags are written (`19h` is always written before `18h` so burst count is set before enabling burst refresh); unrecognized flags exit with errorlevel `1` without touching hardware.
- Cirrus VGA flags (`/V`, `/VIO*`, `/VM*`) probe `SR06` (`12h` unlock readback) **before writing any registers**; if no Cirrus `CL-GD542x` is detected, `ACCTUNE` aborts safely with errorlevel `2` without modifying hardware. Every Cirrus access unlocks `SR06 = 12h`, performs atomic RMW under `CLI`/`STI`, re-locks `SR06 = 00h`, and restores the original `3C4h` index.
- Every ACC write uses atomic read-modify-write under `CLI`/`STI` with `0EDh` I/O delays, preserving unrelated bits (such as L2 cache enable `04h b0`, DRAM burst `04h b4`, Page Mode `05h b4`, and burst RAS width `19h b7:4`).

### Example Output

```text
C:\>ACCTUNE
ACCTUNE - ACC 2046/2168 Chipset & Cirrus VGA Tuner
Regs:  04=54 05=18 0B=05 18=00 19=00
State: PW=OFF RF=/2 BR=OFF AT=ON W486=0WS CASW=2T PWWS=1WS L2=OFF
Flags (opt-in, combinable; omit + to enable):
  /PW+ /PW-       Posted Write ON/OFF (04h b7)
  /R2..16 /R-     DRAM Refresh (/R2,/R4,/R8,/R16; /R=/R4, /R-=/R2)
  /BR1..8 /BR-    Burst Refresh ON (1-8, /BR=4) / OFF (18h b1, 19h b2:0)
  /AT- /AT+       AT Bus Refresh OFF/ON (18h b0)
  /W0+ /W0-       486 0-WS Mem Write ON/OFF (04h b6)
  /C1+ /C1-       1T/2T CAS Write (0Bh b1:0; experimental)
  /P0+ /P0-       0-WS/1-WS Posted Write (18h b4; experimental)
  /V              Read-only Cirrus CL-GD542x VGA register status
  /VIO+ /VIO-     Cirrus VLB 1T/2T I/O RDY# (SR16 b7:6)
  /VM50..64 /VM-  Cirrus MCLK MHz (50/54/55/57/59/61/63/64; /VM=54)
  /OFF            Reset ACC tuned bits to stock (/STOCK, /0)
```

### Recommended `AUTOEXEC.BAT` Profiles

- **Max tested PB430 performance (ACC + onboard Cirrus CL-GD5424/28 VLB):**
  ```bat
  C:\UTILS\ACCTUNE.COM /PW /R8 /BR4 /AT- /VIO /VM57
  ```
  *(Use `/VM54` for a cooler 53.7 MHz MCLK with nearly identical DOOM speed, or omit `/VIO /VM57` on non-Cirrus boards.)*
- **Chipset-only max tested (no VGA changes):**
  ```bat
  C:\UTILS\ACCTUNE.COM /PW /R8 /BR4 /AT-
  ```
- **Balanced everyday profile (Posted Write + `/4` Slow Refresh):**
  ```bat
  C:\UTILS\ACCTUNE.COM /PW /R
  ```
- **Disable Posted Write on the fly or revert ACC / Cirrus tweaks back to stock:**
  ```bat
  C:\UTILS\ACCTUNE.COM /PW-
  C:\UTILS\ACCTUNE.COM /OFF /VIO- /VM-
  ```

## Notes on ISA DMA Digital Audio & Clean Boot

- Apply `ACCTUNE /PW /R` cleanly at boot (in `AUTOEXEC.BAT` before launching games). On real PB430 / ACC2168GT hardware with ISA Sound Blaster / Aztech digital audio, `/PW+` runs cleanly across games after a clean reboot.
- Toggling chipset timing registers mid-session (or leaving other experimental timing registers modified without rebooting) was observed to cause ISA DMA audio crackling until rebooted. If you ever encounter audio crackling with a particular sound card or game, disable Posted Write on the fly with `ACCTUNE /PW-` or revert with `ACCTUNE /OFF`.

## Benchmarks (Real Hardware)

Tested on a **Packard Bell Legend Elite 2038** (PB430 LPX motherboard, ACC Micro 2168GT chipset, 33 MHz FSB, no external L2 cache, PNY QuickChip AMD Am5x86-133 in write-through mode, onboard Cirrus Logic VGA):

| Command | `04h` | `05h` | `0Bh` | `18h` | `19h` | `SR16`/`SR1F` | SpeedSys CPU | DOOM `-timedemo demo3` | Notes |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| Stock BIOS (`/OFF`) | `54h` | `18h` | `05h` | `00h` | `00h` | `D8`/`1C` | `38.53` | `29.08 FPS` | Baseline (50.1 MHz MCLK) |
| `ACCTUNE /PW` | `D4h` | `18h` | `05h` | `00h` | `00h` | `D8`/`1C` | `40.54` | `31.37 FPS` | **+5.2% / +7.9% FPS**, clean audio on fresh boot |
| `ACCTUNE /PW /R` | `D4h` | `19h` | `05h` | `00h` | `00h` | `D8`/`1C` | `40.88` | `31.93 FPS` | **+6.1% / +9.8% FPS**, clean audio on fresh boot |
| `ACCTUNE /PW /R /BR4 /AT-` | `D4h` | `19h` | `05h` | `03h` | `03h` | `D8`/`1C` | `41.00` | `32.21 FPS` | **+6.4% / +10.8% FPS**, higher memory bandwidth |
| `ACCTUNE /PW /R /BR4 /AT- /VM54` | `D4h` | `19h` | `05h` | `03h` | `03h` | `D8`/`1E` | — | `32.38 FPS` | **+11.3% FPS**; 53.7 MHz MCLK crosses Cirrus 0-WS threshold |
| `ACCTUNE /PW /R /BR4 /AT- /VIO /VM57` | `D4h` | `19h` | `05h` | `03h` | `03h` | `18`/`20` | — | `32.43 FPS` | **+11.5% FPS**; 1T VLB I/O + 57.3 MHz MCLK |
| `ACCTUNE /PW /R8 /BR4 /AT- /VIO /VM57` | `D4h` | `1Ah` | `05h` | `03h` | `03h` | `18`/`20` | — | `32.54 FPS` | **+11.9% FPS**; `/8` DRAM refresh + Cirrus VLB tuning |
| `ACCTUNE /PW /C1` | `D4h` | `18h` | `04h` | `00h` | `00h` | `D8`/`1C` | `42.76` | *(unstable)* | Failed SpeedSys extended memtest at 33 MHz on 70 ns SIMMs |
| `ACCTUNE /PW /P0` | `D4h` | `18h` | `05h` | `10h` | `00h` | `D8`/`1C` | `42.76` | *(crashes)* | Crashed DOOM (`R_MapPlane`) within seconds at 33 MHz |

## Register Reference (ACC 2046 / 2168)

Accessed via index port `0F2h` and data port `0F3h`:

| Register | Bits | Function |
| :---: | :---: | :--- |
| `04h` | `7` | Posted Write Enable (`1` = ON, `0` = OFF) |
| `04h` | `6` | Enable 486 Memory Write 0-WS (`1` = 0-WS, `0` = standard) |
| `04h` | `0` | External L2 Cache Enable (read-only in status display; never modified) |
| `05h` | `1:0` | DRAM Refresh divisor (`00` = `/2` stock, `01` = `/4`, `10` = `/8`, `11` = `/16` exp.) |
| `0Bh` | `1:0` | Page-Mode CAS Write pulse width (`00` = 1T, `01` = 2T, `10` = 3T, `11` = 4T) |
| `18h` | `4` | Posted Write Wait States (`0` = 1 WS default, `1` = 0 WS) |
| `18h` | `1` | Enable Burst Refresh (`1` = ON, `0` = OFF) |
| `18h` | `0` | Disable AT Bus Refresh (`1` = disabled, `0` = AT refresh enabled; safe when no ISA DRAM expansion cards are installed) |
| `19h` | `2:0` | Burst Refresh count (`000` = 1 row .. `111` = 8 rows) |

*(Note: `06h` write wait states are intentionally omitted—when the chipset runs in Page Mode `05h b4=1`, `06h` is bypassed in favor of `0Bh`.)*

## Register Reference (Cirrus Logic CL-GD5424 / 5426 / 5428 VLB)

Accessed via Sequencer ports `3C4h`/`3C5h` after unlocking `SR06 = 12h` (always re-locked to `00h` afterward):

| Register | Bits | Function |
| :---: | :---: | :--- |
| `SR06` | `7:0` | Extension Unlock (`12h` = unlocked, `00h` = re-locked / reads `0Fh`) |
| `SR16` | `7:6` | VLB I/O `RDY#` delay (`00`/`01` = 1T `/VIO+`, `10`/`11` = 2T `/VIO-`); `b5:4` (VLB Mem Write `RDY#`, already 0-WS at 33 MHz) and `b3:0` (CRT FIFO threshold) are preserved |
| `SR1F` | `5:0` | MCLK = `1.78977 MHz × val` (`1Ch`=50.1, `1Eh`=53.7, `1Fh`=55.5, `20h`=57.3, `21h`=59.1, `22h`=60.9, `23h`=62.6, `24h`=64.4 MHz); `b7:6` are preserved |

## Compatibility & Safety

- **BIOS-independent:** Works across PB430 revisions and other **ACC Micro 2046 / 2168 / 2168GT** 486 motherboards, with or without external L2 cache.
- **ACC chipsets only:** `ACCTUNE.COM` does not probe for a chipset ID—do **not** run it on non-ACC motherboards (OPTi, SiS, UMC, Intel, VIA, etc.).
- **Experimental flags (`/C1`, `/P0`, `/R16`):** Included for systems running faster 60 ns FPM SIMMs or slower 25 MHz bus clocks. Always validate with SpeedSys extended memory test and real workloads.
- **Slow Refresh (`/R4`, `/R8`, `/R16`):** Runs DRAM refresh slower than strict spec; verify stability after idling a few minutes on your specific SIMMs (avoid `/R16` on older warm FPM SIMMs).
- **Cirrus MCLK (`/VM54`..`/VM64`):** Official 5424/26/28 rating is 50 MHz (`1Ch`). Raising MCLK to `53.7 MHz` (`/VM54`) crosses Cirrus's `3×T_MCLK + 2ns < 60ns` 33 MHz VLB write threshold; `57.3 MHz` (`/VM57`) is a safe sweet spot with SVGA headroom. Back down 1–2 steps if any pixel snow appears.

## Building from Source

With [NASM](https://www.nasm.us/):

```sh
nasm -f bin acctune.asm -o ACCTUNE.COM
```

Or on Windows with zero external dependencies (assembles `acctune.asm` directly and runs a 34-case 8086 emulation test suite):

```powershell
.\build.ps1
```

Expected SHA-256 of `ACCTUNE.COM` (2,585 bytes):

```text
69F05F67392674B0ACA163F697AE1DC4978696CB9B5C9D55422FB636E0EC7A61
```

## License

[MIT](LICENSE)

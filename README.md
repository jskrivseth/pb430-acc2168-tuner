# pb430-acc2168-tuner (`ACCTUNE.COM`)

A tiny (1,729-byte) pure 16-bit MS-DOS opt-in chipset tuner for **ACC Micro 2046 / 2168 / 2168GT** 486 motherboards, developed and real-hardware tested on a **Packard Bell PB430** (Legend Elite 2038).

Running `ACCTUNE` with **no arguments** is completely **read-only**: it prints the live ACC2168 register values (`04h`, `05h`, `0Bh`, `18h`, `19h`), decoded state, and usage help without modifying hardware. Every tweak is strictly opt-in, combinable, and reversible.

## Usage

```text
ACCTUNE                     Read-only register status + help (no writes)
ACCTUNE /PW+  | /PW-        Posted Write ON/OFF (04h b7)
ACCTUNE /R+   | /R-         Slow DRAM Refresh ON/OFF (05h b1:0)
ACCTUNE /BR1..8 | /BR-      Burst Refresh ON (1-8 rows, /BR=4) / OFF (18h b1, 19h b2:0)
ACCTUNE /AT-  | /AT+        AT Bus Refresh OFF/ON (18h b0: 1=disabled, 0=stock)
ACCTUNE /W0+  | /W0-        486 0-WS Mem Write ON/OFF (04h b6)
ACCTUNE /C1+  | /C1-        1T/2T CAS Write pulse (0Bh b1:0: 00=1T, 01=2T; experimental)
ACCTUNE /P0+  | /P0-        0-WS/1-WS Posted Write (18h b4; experimental)
ACCTUNE /OFF                Reset all tuned bits back to safe stock (also /STOCK, /0)
```

- Flags are **case-insensitive**, accept `/` or `-`, and **omit `+` as shorthand to enable** (e.g. `ACCTUNE /PW /R /BR4 /AT-`; `/BR` defaults to 4-row burst).
- Flags are **combinable** in one command (e.g. `ACCTUNE /PW /R /BR4 /AT-`, `ACCTUNE /PW /R /BR8 /AT-`, `ACCTUNE /PW- /R+`).
- Only registers explicitly referenced by your flags are written (`19h` is always written before `18h` so burst count is set before enabling burst refresh); unrecognized flags exit with errorlevel `1` without touching hardware.
- Every write uses atomic read-modify-write under `CLI`/`STI` with `0EDh` I/O delays, preserving unrelated bits (such as L2 cache enable `04h b0`, DRAM burst `04h b4`, Page Mode `05h b4`, and burst RAS width `19h b7:4`).

### Example Output

```text
C:\>ACCTUNE
ACCTUNE - ACC 2046/2168 Chipset Tuner
Regs:  04=54 05=18 0B=05 18=00 19=00
State: PW=OFF RF=STD BR=OFF AT=ON W486=0WS CASW=2T PWWS=1WS L2=OFF
Flags (opt-in, combinable; omit + to enable):
  /PW+ /PW-     Posted Write ON/OFF (04h b7)
  /R+  /R-      Slow DRAM Refresh ON/OFF (05h b1:0)
  /BR1..8 /BR-  Burst Refresh ON (1-8, /BR=4) / OFF (18h b1, 19h b2:0)
  /AT- /AT+     AT Bus Refresh OFF/ON (18h b0)
  /W0+ /W0-     486 0-WS Mem Write ON/OFF (04h b6)
  /C1+ /C1-     1T/2T CAS Write (0Bh b1:0; experimental)
  /P0+ /P0-     0-WS/1-WS Posted Write (18h b4; experimental)
  /OFF          Reset all tuned bits to stock (/STOCK, /0)
```

### Recommended `AUTOEXEC.BAT` Profiles

- **Max tested performance (Posted Write + Slow Refresh + Burst Refresh 4 + AT Refresh OFF):**
  ```bat
  C:\UTILS\ACCTUNE.COM /PW /R /BR4 /AT-
  ```
  *(Try `/BR8` for 8-row burst refresh if your SIMMs pass SpeedSys extended memtest.)*
- **Balanced everyday profile (Posted Write + Slow Refresh):**
  ```bat
  C:\UTILS\ACCTUNE.COM /PW /R
  ```
- **Conservative fallback (Slow DRAM Refresh only):**
  ```bat
  C:\UTILS\ACCTUNE.COM /R
  ```
- **Disable Posted Write on the fly or revert everything back to stock:**
  ```bat
  C:\UTILS\ACCTUNE.COM /PW-
  C:\UTILS\ACCTUNE.COM /OFF
  ```

## Notes on ISA DMA Digital Audio & Clean Boot

- Apply `ACCTUNE /PW /R` cleanly at boot (in `AUTOEXEC.BAT` before launching games). On real PB430 / ACC2168GT hardware with ISA Sound Blaster / Aztech digital audio, `/PW+` runs cleanly across games after a clean reboot.
- Toggling chipset timing registers mid-session (or leaving other experimental timing registers modified without rebooting) was observed to cause ISA DMA audio crackling until rebooted. If you ever encounter audio crackling with a particular sound card or game, disable Posted Write on the fly with `ACCTUNE /PW-` or revert with `ACCTUNE /OFF`.

## Benchmarks (Real Hardware)

Tested on a **Packard Bell Legend Elite 2038** (PB430 LPX motherboard, ACC Micro 2168GT chipset, 33 MHz FSB, no external L2 cache, PNY QuickChip AMD Am5x86-133 in write-through mode, onboard Cirrus Logic VGA):

| Command | `04h` | `05h` | `0Bh` | `18h` | `19h` | SpeedSys CPU | DOOM `-timedemo demo3` | Notes |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| Stock BIOS (`/OFF`) | `54h` | `18h` | `05h` | `00h` | `00h` | `38.53` | `29.08 FPS` | Baseline |
| `ACCTUNE /PW` | `D4h` | `18h` | `05h` | `00h` | `00h` | `40.54` | `31.37 FPS` | **+5.2% / +7.9% FPS**, clean audio on fresh boot |
| `ACCTUNE /PW /R` | `D4h` | `19h` | `05h` | `00h` | `00h` | `40.88` | `31.93 FPS` | **+6.1% / +9.8% FPS**, clean audio on fresh boot |
| `ACCTUNE /PW /R /BR4 /AT-` | `D4h` | `19h` | `05h` | `03h` | `03h` | `41.00` | `32.21 FPS` | **+6.4% / +10.8% FPS**, higher memory bandwidth |
| `ACCTUNE /PW /C1` | `D4h` | `18h` | `04h` | `00h` | `00h` | `42.76` | *(unstable)* | Failed SpeedSys extended memtest at 33 MHz on 70 ns SIMMs |
| `ACCTUNE /PW /P0` | `D4h` | `18h` | `05h` | `10h` | `00h` | `42.76` | *(crashes)* | Crashed DOOM (`R_MapPlane`) within seconds at 33 MHz |

## Register Reference (ACC 2046 / 2168)

Accessed via index port `0F2h` and data port `0F3h`:

| Register | Bits | Function |
| :---: | :---: | :--- |
| `04h` | `7` | Posted Write Enable (`1` = ON, `0` = OFF) |
| `04h` | `6` | Enable 486 Memory Write 0-WS (`1` = 0-WS, `0` = standard) |
| `04h` | `0` | External L2 Cache Enable (read-only in status display; never modified) |
| `05h` | `1:0` | DRAM Refresh divisor (`00` = standard, `01` = slower refresh) |
| `0Bh` | `1:0` | Page-Mode CAS Write pulse width (`00` = 1T, `01` = 2T, `10` = 3T, `11` = 4T) |
| `18h` | `4` | Posted Write Wait States (`0` = 1 WS default, `1` = 0 WS) |
| `18h` | `1` | Enable Burst Refresh (`1` = ON, `0` = OFF) |
| `18h` | `0` | Disable AT Bus Refresh (`1` = disabled, `0` = AT refresh enabled; safe when no ISA DRAM expansion cards are installed) |
| `19h` | `2:0` | Burst Refresh count (`000` = 1 row .. `111` = 8 rows) |

*(Note: `06h` write wait states are intentionally omitted—when the chipset runs in Page Mode `05h b4=1`, `06h` is bypassed in favor of `0Bh`.)*

## Compatibility & Safety

- **BIOS-independent:** Works across PB430 revisions and other **ACC Micro 2046 / 2168 / 2168GT** 486 motherboards, with or without external L2 cache.
- **ACC chipsets only:** `ACCTUNE.COM` does not probe for a chipset ID—do **not** run it on non-ACC motherboards (OPTi, SiS, UMC, Intel, VIA, etc.).
- **Experimental flags (`/C1`, `/P0`):** Included for systems running faster 60 ns FPM SIMMs or slower 25 MHz bus clocks. Always validate with SpeedSys extended memory test and real workloads.
- **Slow Refresh (`/R`):** Runs DRAM refresh slower than strict spec; verify stability after idling a few minutes on your specific SIMMs.

## Building from Source

With [NASM](https://www.nasm.us/):

```sh
nasm -f bin acctune.asm -o ACCTUNE.COM
```

Or on Windows with zero external dependencies (assembles `acctune.asm` directly and runs a 23-case 8086 emulation test suite):

```powershell
.\build.ps1
```

Expected SHA-256 of `ACCTUNE.COM` (1,729 bytes):

```text
E468E659537164377C1F7702E04630A64CFFB29C901C7B870C7E9471E496BC66
```

## License

[MIT](LICENSE)

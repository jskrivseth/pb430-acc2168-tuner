# pb430-acc2168-tuner (`ACCTUNE.COM`)

A tiny (1,408-byte) pure 16-bit MS-DOS opt-in chipset tuner for **ACC Micro 2046 / 2168 / 2168GT** 486 motherboards, developed and real-hardware tested on a **Packard Bell PB430** (Legend Elite 2038).

Running `ACCTUNE` with **no arguments** is completely **read-only**: it prints the live ACC2168 register values (`04h`, `05h`, `0Bh`, `18h`), decoded state, and usage help without modifying hardware. Every tweak is strictly opt-in, combinable, and reversible.

## Usage

```text
ACCTUNE                     Read-only register status + help (no writes)
ACCTUNE /PW+  | /PW-        Posted Write ON/OFF (04h b7; may crackle ISA DMA audio)
ACCTUNE /R+   | /R-         Slow DRAM Refresh ON/OFF (05h b1:0; audio-safe)
ACCTUNE /W0+  | /W0-        486 0-WS Mem Write ON/OFF (04h b6)
ACCTUNE /C1+  | /C1-        1T/2T CAS Write pulse (0Bh b1:0: 00=1T, 01=2T; experimental)
ACCTUNE /P0+  | /P0-        0-WS/1-WS Posted Write (18h b4; experimental)
ACCTUNE /OFF                Reset all tuned bits back to safe stock (also /STOCK, /0)
```

- Flags are **case-insensitive**, accept `/` or `-`, and **omit `+` as shorthand to enable** (e.g. `ACCTUNE /R` is identical to `ACCTUNE /R+`).
- Flags are **combinable** in one command (e.g. `ACCTUNE /PW /R`, `ACCTUNE /PW- /R+`, `ACCTUNE /PW+/R+`).
- Only registers explicitly referenced by your flags are written; unrecognized flags exit with errorlevel `1` without touching hardware.
- Every write uses atomic read-modify-write under `CLI`/`STI` with `0EDh` I/O delays, preserving unrelated bits (such as L2 cache enable `04h b0`, DRAM burst `04h b4`, and Page Mode `05h b4`).

### Example Output

```text
C:\>ACCTUNE
ACCTUNE - ACC 2046/2168 Chipset Tuner
Regs:  04=54 05=18 0B=05 18=00
State: PW=OFF RF=STD W486=0WS CASW=2T PWWS=1WS L2=OFF
Flags (opt-in, combinable; omit + to enable):
  /PW+ /PW-  Posted Write ON/OFF (04h b7; may crackle ISA DMA audio)
  /R+  /R-   Slow DRAM Refresh ON/OFF (05h b1:0; audio-safe)
  /W0+ /W0-  486 0-WS Mem Write ON/OFF (04h b6)
  /C1+ /C1-  1T/2T CAS Write (0Bh b1:0; experimental)
  /P0+ /P0-  0-WS/1-WS Posted Write (18h b4; experimental)
  /OFF       Reset all tuned bits to stock (/STOCK, /0)
```

### Recommended `AUTOEXEC.BAT` Profiles

- **Everyday DOS gaming with ISA Sound Blaster / Aztech digital audio:**
  ```bat
  C:\UTILS\ACCTUNE.COM /R
  ```
- **Max performance (benchmarks, silent/FM-only games, non-DMA workloads):**
  ```bat
  C:\UTILS\ACCTUNE.COM /PW /R
  ```
- **Quickly silence ISA DMA audio crackling before launching a game:**
  ```bat
  C:\UTILS\ACCTUNE.COM /PW-
  ```
  Or revert everything back to stock:
  ```bat
  C:\UTILS\ACCTUNE.COM /OFF
  ```

## Important Caveat: ISA DMA Digital Audio & Posted Write (`/PW`)

On real PB430 / ACC2168GT hardware, enabling **Posted Write (`04h` bit 7)** causes audible **crackling in ISA DMA digital audio** (Sound Blaster / Aztech PCM playback), both with `04h=D4h` (`W0+`) and `04h=94h` (`W0-`), regardless of DRAM refresh setting.

- This is almost certainly why Packard Bell left Posted Write disabled in the PB430 BIOS (Packard Bell Legends shipped with ISA sound cards).
- Disabling Posted Write (`ACCTUNE /PW-` or `ACCTUNE /OFF`) removes the crackling immediately.
- **Slow DRAM Refresh (`/R`) alone does not cause audio crackling**, making `ACCTUNE /R` the cleanest always-on tweak for sound-card gaming.

## Benchmarks (Real Hardware)

Tested on a **Packard Bell Legend Elite 2038** (PB430 LPX motherboard, ACC Micro 2168GT chipset, 33 MHz FSB, no external L2 cache, PNY QuickChip AMD Am5x86-133 in write-through mode, onboard Cirrus Logic VGA):

| Command | `04h` | `05h` | `0Bh` | `18h` | SpeedSys CPU | DOOM `-timedemo demo3` | Notes |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| Stock BIOS (`/OFF`) | `54h` | `18h` | `05h` | `00h` | `38.53` | `29.08 FPS` | Baseline, clean audio |
| `ACCTUNE /PW` | `D4h` | `18h` | `05h` | `00h` | `40.54` | `31.37 FPS` | **+5.2% / +7.9% FPS**; ISA DMA audio crackles |
| `ACCTUNE /PW /R` | `D4h` | `19h` | `05h` | `00h` | `40.88` | `31.93 FPS` | **+6.1% / +9.8% FPS**; ISA DMA audio crackles |
| `ACCTUNE /PW /C1` | `D4h` | `18h` | `04h` | `00h` | `42.76` | *(unstable)* | Failed SpeedSys extended memtest at 33 MHz on 70 ns SIMMs |
| `ACCTUNE /PW /P0` | `D4h` | `18h` | `05h` | `10h` | `42.76` | *(crashes)* | Crashed DOOM (`R_MapPlane`) within seconds at 33 MHz |

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

Or on Windows with zero external dependencies (assembles `acctune.asm` directly and runs a 17-case 8086 emulation test suite):

```powershell
.\build.ps1
```

Expected SHA-256 of `ACCTUNE.COM` (1,408 bytes):

```text
F1D8FF932408E33CBA01B6245BC348D9171A0DD5926F30A36E667800910754A5
```

## License

[MIT](LICENSE)

# pb430-acc2168-tuner (`POSTWR.COM`)

A tiny (279-byte) 16-bit MS-DOS utility to enable **Posted Writes**—and optionally **slower DRAM refresh**—on **ACC Micro 2046 / 2168 / 2168GT** 486 chipsets, developed and hardware-tested on a **Packard Bell PB430** (Legend Elite 2038).

Many OEM ACC2168 BIOSes (including the Packard Bell PB430 Phoenix A486 BIOS) leave chipset Posted Write disabled at boot (`reg 04h` bit 7 = `0`), leaving noticeable memory write bandwidth and 3D game performance on the table.

## Usage

Copy `POSTWR.COM` to your DOS drive (e.g. `C:\UTILS\POSTWR.COM`) and run it manually or from `AUTOEXEC.BAT`:

| Command | Action | ACC2168 Registers |
| :--- | :--- | :--- |
| `POSTWR` | Enable Posted Write, keep stock DRAM refresh (in-spec) | `04h \|= 80h`, `05h &= FCh` |
| `POSTWR /R` | Enable Posted Write **and** slower DRAM refresh (also accepts `/r`, `-R`, `-r`) | `04h \|= 80h`, `05h = (05h & FCh) \| 01h` |
| `POSTWR /OFF` | Undo both back to stock (also accepts `-off`, `/O`, `/0`) | `04h &= 7Fh`, `05h &= FCh` |

Every invocation explicitly sets both registers via read-modify-write under `CLI`/`STI` with `0EDh` I/O delays, so it is safe to run repeatedly in any order:
- Running `POSTWR` after `POSTWR /R` turns slow refresh back to stock.
- Running `POSTWR /OFF` restores both bits to stock (`04h=54h`, `05h=18h` on a cacheless 33 MHz PB430).

### `AUTOEXEC.BAT` example

```bat
C:\UTILS\POSTWR.COM
```

Or with the optional slower DRAM refresh:

```bat
C:\UTILS\POSTWR.COM /R
```

## Benchmarks (Real Hardware)

Tested on a **Packard Bell Legend Elite 2038** (PB430 LPX motherboard, ACC Micro 2168GT chipset, 33 MHz FSB, no external L2 cache, PNY QuickChip AMD Am5x86-133 in write-through mode, onboard Cirrus Logic VGA):

| Configuration | `04h` | `05h` | SpeedSys CPU | DOOM `-timedemo demo3` | Gain vs Stock |
| :--- | :---: | :---: | :---: | :---: | :---: |
| Stock BIOS | `54h` | `18h` | `38.53` | `29.08 FPS` | baseline |
| `POSTWR` | `D4h` | `18h` | `40.54` | `31.37 FPS` | **+5.2% / +7.9% FPS** |
| `POSTWR /R` | `D4h` | `19h` | `40.88` | `31.93 FPS` | **+6.1% / +9.8% FPS** |

## Technical Notes

- **Chipset I/O interface:** ACC Micro 2046/2168 configuration index port `0F2h`, data port `0F3h`.
- **`reg 04h` bit 7:** Posted Write Enable (`1` = enabled, `0` = disabled). All other bits (L2 cache enable, DRAM burst, 0-WS 486 mem write, line size) are preserved untouched.
- **`reg 05h` bits `1:0`:** DRAM refresh divisor (`00` = normal/stock, `01` = reduced refresh overhead). Page Mode (`bit 4`) and all other bits are preserved untouched.
- **Why other aggressive registers are intentionally excluded:**
  - `reg 18h` bit 4 (`0-WS Posted Write`, `10h`): passed quick synthetic tests on PB430 at 33 MHz but crashed DOOM (`R_MapPlane`) within seconds.
  - `reg 18h` bit 5 (`Disable 1T sampling delay`, `20h`): caused immediate memory corruption at 33 MHz.
  - `reg 0Bh` bits `1:0` (`1T CAS write`, `04h` vs stock `05h`): failed SpeedSys extended memory test at 33 MHz.
  - `reg 06h` bits `7:6` (write wait states): bypassed when the chipset is operating in Page Mode (`05h` bit 4 = `1`), where `0Bh` governs CAS/RAS timings.

## Compatibility & Safety

- **BIOS-independent:** Talks directly to ACC chipset registers rather than patching BIOS code; works across PB430 revisions and other **ACC Micro 2046 / 2168 / 2168GT** motherboards.
- **ACC chipsets only:** `POSTWR.COM` does not probe for a chipset ID—do **not** run it on non-ACC motherboards (OPTi, SiS, UMC, Intel, VIA, etc.).
- **`/R` stability note:** Slower DRAM refresh (`05h` b1:0 = `01`) reduces refresh overhead outside strict DRAM spec. Most 60 ns / 70 ns FPM SIMMs handle it fine at room temperature, but verify with a memory test and an idle soak on your specific RAM.

## Building from Source

With [NASM](https://www.nasm.us/):

```sh
nasm -f bin postwr.asm -o POSTWR.COM
```

Or on Windows with zero external tools (also runs a 12-case 8086 emulation test):

```powershell
.\build.ps1
```

Expected SHA-256 of `POSTWR.COM` (279 bytes):

```text
3A952A2890B45C70DC4B733E12A0F837126B38B1060EC8CDD169B37DDB160C78
```

## License

[MIT](LICENSE)

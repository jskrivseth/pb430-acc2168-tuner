# Zero-dependency PowerShell builder and 8086 verifier for POSTWR.COM
# Produces the exact same 279-byte binary as: nasm -f bin postwr.asm -o POSTWR.COM
$ErrorActionPreference = 'Stop'

function Assemble-PostWr {
    $org = 0x0100
    $labels = @{}
    for ($pass = 1; $pass -le 2; $pass++) {
        $buf = New-Object System.Collections.Generic.List[byte]
        $emit = { param([byte[]]$b) $buf.AddRange($b) }
        $here = { $org + $buf.Count }
        $rel8 = {
            param([string]$lbl)
            if ($pass -eq 1) { return [byte]0 }
            $disp = $labels[$lbl] - (($org + $buf.Count) + 1)
            if ($disp -lt -128 -or $disp -gt 127) { throw "rel8 out of range for $lbl : $disp" }
            return [byte]($disp -band 0xFF)
        }
        $addr16 = {
            param([string]$lbl)
            if ($pass -eq 1) { return [byte[]]@(0, 0) }
            $a = $labels[$lbl]
            return [byte[]]@([byte]($a -band 0xFF), [byte](($a -shr 8) -band 0xFF))
        }

        & $emit @(0xBE, 0x81, 0x00)
        & $emit @(0x31, 0xC9)
        & $emit @(0x8A, 0x0E, 0x80, 0x00)
        & $emit @(0x30, 0xDB)
        & $emit @(0xFC)
        & $emit @(0xE3); & $emit @(& $rel8 'apply')

        $labels['scan'] = & $here
        & $emit @(0xAC)
        & $emit @(0x3C, 0x2F)
        & $emit @(0x74); & $emit @(& $rel8 'check_flag')
        & $emit @(0x3C, 0x2D)
        & $emit @(0x75); & $emit @(& $rel8 'next_ch')

        $labels['check_flag'] = & $here
        & $emit @(0x49)
        & $emit @(0x74); & $emit @(& $rel8 'apply')
        & $emit @(0xAC)
        & $emit @(0x3C, 0x30)
        & $emit @(0x74); & $emit @(& $rel8 'set_off')
        & $emit @(0x0C, 0x20)
        & $emit @(0x3C, 0x72)
        & $emit @(0x74); & $emit @(& $rel8 'set_r')
        & $emit @(0x3C, 0x6F)
        & $emit @(0x75); & $emit @(& $rel8 'next_ch')

        $labels['set_off'] = & $here
        & $emit @(0xB3, 0x02)
        & $emit @(0xEB); & $emit @(& $rel8 'next_ch')

        $labels['set_r'] = & $here
        & $emit @(0xB3, 0x01)

        $labels['next_ch'] = & $here
        & $emit @(0xE2); & $emit @(& $rel8 'scan')

        $labels['apply'] = & $here
        & $emit @(0xFA)

        # reg 04h
        & $emit @(0xB0, 0x04)
        & $emit @(0xE6, 0xF2)
        & $emit @(0xE6, 0xED)
        & $emit @(0xE4, 0xF3)
        & $emit @(0x80, 0xFB, 0x02)
        & $emit @(0x74); & $emit @(& $rel8 'pw_off')
        & $emit @(0x0C, 0x80)
        & $emit @(0xEB); & $emit @(& $rel8 'write_04')
        $labels['pw_off'] = & $here
        & $emit @(0x24, 0x7F)
        $labels['write_04'] = & $here
        & $emit @(0x8A, 0xE0)
        & $emit @(0xB0, 0x04)
        & $emit @(0xE6, 0xF2)
        & $emit @(0xE6, 0xED)
        & $emit @(0x8A, 0xC4)
        & $emit @(0xE6, 0xF3)
        & $emit @(0xE6, 0xED)

        # reg 05h
        & $emit @(0xB0, 0x05)
        & $emit @(0xE6, 0xF2)
        & $emit @(0xE6, 0xED)
        & $emit @(0xE4, 0xF3)
        & $emit @(0x24, 0xFC)
        & $emit @(0x80, 0xFB, 0x01)
        & $emit @(0x75); & $emit @(& $rel8 'write_05')
        & $emit @(0x0C, 0x01)
        $labels['write_05'] = & $here
        & $emit @(0x8A, 0xE0)
        & $emit @(0xB0, 0x05)
        & $emit @(0xE6, 0xF2)
        & $emit @(0xE6, 0xED)
        & $emit @(0x8A, 0xC4)
        & $emit @(0xE6, 0xF3)
        & $emit @(0xE6, 0xED)

        & $emit @(0xFB)

        & $emit @(0xBA); & $emit (& $addr16 'msg_pw')
        & $emit @(0x80, 0xFB, 0x01)
        & $emit @(0x75); & $emit @(& $rel8 'chk_off_msg')
        & $emit @(0xBA); & $emit (& $addr16 'msg_both')
        & $emit @(0xEB); & $emit @(& $rel8 'print_msg')
        $labels['chk_off_msg'] = & $here
        & $emit @(0x80, 0xFB, 0x02)
        & $emit @(0x75); & $emit @(& $rel8 'print_msg')
        & $emit @(0xBA); & $emit (& $addr16 'msg_off')

        $labels['print_msg'] = & $here
        & $emit @(0xB4, 0x09)
        & $emit @(0xCD, 0x21)
        & $emit @(0xB8, 0x00, 0x4C)
        & $emit @(0xCD, 0x21)

        $labels['msg_pw'] = & $here
        & $emit ([System.Text.Encoding]::ASCII.GetBytes("POSTWR: Posted Write ON, Refresh Stock`r`n`$"))

        $labels['msg_both'] = & $here
        & $emit ([System.Text.Encoding]::ASCII.GetBytes("POSTWR: Posted Write ON, Slow Refresh ON`r`n`$"))

        $labels['msg_off'] = & $here
        & $emit ([System.Text.Encoding]::ASCII.GetBytes("POSTWR: Stock (Posted Write OFF, Refresh Stock)`r`n`$"))
    }
    return $buf.ToArray()
}

$outPath = Join-Path $PSScriptRoot 'POSTWR.COM'
$bytes = Assemble-PostWr
[System.IO.File]::WriteAllBytes($outPath, $bytes)

# Self-test compiled machine code in a minimal 8086 emulator
$regs = @{ 0x04 = 0x54; 0x05 = 0x18 }
function Test-Case([string]$cmdTail, [byte]$exp04, [byte]$exp05) {
    $mem = New-Object byte[] 0x1000
    $tailBytes = [System.Text.Encoding]::ASCII.GetBytes($cmdTail)
    $mem[0x80] = [byte]$tailBytes.Length
    for ($i = 0; $i -lt $tailBytes.Length; $i++) { $mem[0x81 + $i] = $tailBytes[$i] }
    $mem[0x81 + $tailBytes.Length] = 0x0D
    [Array]::Copy($bytes, 0, $mem, 0x100, $bytes.Length)

    $ax=0; $bx=0; $cx=0x9999; $dx=0; $si=0; $ip=0x100
    $zf=$false; $df=$true; $iflag=$true
    $idx = 0; $ioWhileIfOn = $false; $out = ""; $exitCode = -1
    $s8 = { param([byte]$b) if ($b -ge 128) { $b - 256 } else { [int]$b } }

    for ($step = 0; $step -lt 500; $step++) {
        $op = $mem[$ip++]
        switch ($op) {
            0xBE { $si = [int]$mem[$ip] + (([int]$mem[$ip+1]) -shl 8); $ip += 2 }
            0xBA { $dx = [int]$mem[$ip] + (([int]$mem[$ip+1]) -shl 8); $ip += 2 }
            0xB8 { $ax = [int]$mem[$ip] + (([int]$mem[$ip+1]) -shl 8); $ip += 2 }
            0xB0 { $ax = ($ax -band 0xFF00) -bor [int]$mem[$ip++] }
            0xB3 { $bx = ($bx -band 0xFF00) -bor [int]$mem[$ip++] }
            0xB4 { $ax = ($ax -band 0x00FF) -bor (([int]$mem[$ip++]) -shl 8) }
            0x31 { if ($mem[$ip++] -ne 0xC9) { throw "bad 31" }; $cx = 0; $zf = $true }
            0x30 { if ($mem[$ip++] -ne 0xDB) { throw "bad 30" }; $bx = $bx -band 0xFF00; $zf = $true }
            0x80 { if ($mem[$ip++] -ne 0xFB) { throw "bad 80" }; $zf = (($bx -band 0xFF) -eq [int]$mem[$ip++]) }
            0x8A {
                $rm = $mem[$ip++]
                if ($rm -eq 0x0E) { $addr = [int]$mem[$ip] + (([int]$mem[$ip+1]) -shl 8); $ip += 2; $cx = ($cx -band 0xFF00) -bor [int]$mem[$addr] }
                elseif ($rm -eq 0xE0) { $ax = (($ax -band 0xFF) -shl 8) -bor ($ax -band 0xFF) }
                elseif ($rm -eq 0xC4) { $ax = ($ax -band 0xFF00) -bor (($ax -shr 8) -band 0xFF) }
                else { throw "bad 8A" }
            }
            0xFC { $df = $false }
            0xFA { $iflag = $false }
            0xFB { $iflag = $true }
            0xAC { $ax = ($ax -band 0xFF00) -bor [int]$mem[$si]; $si += $(if ($df) { -1 } else { 1 }) }
            0x3C { $zf = (($ax -band 0xFF) -eq [int]$mem[$ip++]) }
            0x0C { $v = ($ax -band 0xFF) -bor [int]$mem[$ip++]; $ax = ($ax -band 0xFF00) -bor $v; $zf = ($v -eq 0) }
            0x24 { $v = ($ax -band 0xFF) -band [int]$mem[$ip++]; $ax = ($ax -band 0xFF00) -bor $v; $zf = ($v -eq 0) }
            0x49 { $cx = ($cx - 1) -band 0xFFFF; $zf = ($cx -eq 0) }
            0xE3 { $d = & $s8 $mem[$ip++]; if ($cx -eq 0) { $ip += $d } }
            0x74 { $d = & $s8 $mem[$ip++]; if ($zf) { $ip += $d } }
            0x75 { $d = & $s8 $mem[$ip++]; if (-not $zf) { $ip += $d } }
            0xEB { $d = & $s8 $mem[$ip++]; $ip += $d }
            0xE2 { $d = & $s8 $mem[$ip++]; $cx = ($cx - 1) -band 0xFFFF; if ($cx -ne 0) { $ip += $d } }
            0xE6 {
                $port = $mem[$ip++]; $al = $ax -band 0xFF
                if ($iflag) { $ioWhileIfOn = $true }
                if ($port -eq 0xF2) { $idx = $al }
                elseif ($port -eq 0xF3) { $regs[$idx] = $al }
                elseif ($port -ne 0xED) { throw "unexpected OUT port $port" }
            }
            0xE4 {
                if ($iflag) { $ioWhileIfOn = $true }
                if ($mem[$ip++] -ne 0xF3) { throw "unexpected IN port" }
                $ax = ($ax -band 0xFF00) -bor $regs[$idx]
            }
            0xCD {
                if ($mem[$ip++] -ne 0x21) { throw "unexpected INT" }
                $ah = ($ax -shr 8) -band 0xFF
                if ($ah -eq 0x09) {
                    $p = $dx
                    while ($mem[$p] -ne 0x24) { $out += [char]$mem[$p++] }
                } elseif ($ah -eq 0x4C) {
                    $exitCode = $ax -band 0xFF; break
                } else { throw "unexpected INT 21 AH=$ah" }
            }
            default { throw ("Unknown opcode {0:X2}" -f $op) }
        }
        if ($exitCode -ge 0) { break }
    }
    if ($regs[4] -ne $exp04 -or $regs[5] -ne $exp05 -or -not $iflag -or $ioWhileIfOn -or $exitCode -ne 0) {
        throw "Verification failed for '$cmdTail': got 04=$($regs[4].ToString('X2')) 05=$($regs[5].ToString('X2'))"
    }
}

Test-Case ""         0xD4 0x18
Test-Case " /R"      0xD4 0x19
Test-Case " /R"      0xD4 0x19
Test-Case ""         0xD4 0x18
Test-Case " /OFF"    0x54 0x18
Test-Case " /r"      0xD4 0x19
Test-Case " -off"    0x54 0x18
Test-Case " /R"      0xD4 0x19
Test-Case " /0"      0x54 0x18
Test-Case " /R /OFF" 0x54 0x18
Test-Case " /OFF /R" 0xD4 0x19
Test-Case " /"       0xD4 0x18

$hash = (Get-FileHash $outPath -Algorithm SHA256).Hash
Write-Host "Built $outPath ($($bytes.Length) bytes), 12/12 emulation tests passed."
Write-Host "SHA256: $hash"

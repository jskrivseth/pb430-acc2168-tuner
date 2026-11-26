# Zero-dependency PowerShell 8086 assembler + emulator verifier for ACCTUNE.COM
# Assembles acctune.asm directly (matching: nasm -f bin acctune.asm -o ACCTUNE.COM)
$ErrorActionPreference = 'Stop'

$r8Map  = @{ al=0; cl=1; dl=2; bl=3; ah=4; ch=5; dh=6; bh=7 }
$r16Map = @{ ax=0; cx=1; dx=2; bx=3; sp=4; bp=5; si=6; di=7 }
$rmBase = @{ si=4; di=5; bx=7 }
$jccMap = @{ je=0x74; jz=0x74; jne=0x75; jnz=0x75; jb=0x72; jae=0x73; jbe=0x76; ja=0x77 }

function Parse-Imm([string]$s, [hashtable]$labels, [int]$pass) {
    $t = $s.Trim()
    if ($t -match "^'(.)'$") { return [int][char]$Matches[1] }
    if ($t -match '^0[xX]([0-9A-Fa-f]+)$') { return [Convert]::ToInt32($Matches[1], 16) }
    if ($t -match '^([0-9][0-9A-Fa-f]*)[hH]$') { return [Convert]::ToInt32($Matches[1], 16) }
    if ($t -match '^[0-9]+$') { return [int]$t }
    if ($labels.ContainsKey($t)) { return [int]$labels[$t] }
    if ($pass -eq 1) { return 0 }
    throw "Unknown symbol/immediate: $t"
}

function Parse-DbArgs([string]$rest) {
    $out = New-Object System.Collections.Generic.List[byte]
    $i = 0; $n = $rest.Length
    while ($i -lt $n) {
        while ($i -lt $n -and ($rest[$i] -eq ' ' -or $rest[$i] -eq "`t" -or $rest[$i] -eq ',')) { $i++ }
        if ($i -ge $n) { break }
        if ($rest[$i] -eq "'") {
            $i++
            while ($i -lt $n -and $rest[$i] -ne "'") { $out.Add([byte][char]$rest[$i]); $i++ }
            if ($i -lt $n -and $rest[$i] -eq "'") { $i++ }
        } else {
            $start = $i
            while ($i -lt $n -and $rest[$i] -ne ',') { $i++ }
            $tok = $rest.Substring($start, $i - $start).Trim()
            if ($tok.Length -gt 0) {
                $val = Parse-Imm $tok @{} 2
                $out.Add([byte]($val -band 0xFF))
            }
        }
    }
    return $out.ToArray()
}

function Assemble-Asm([string]$asmPath) {
    $lines = Get-Content -Path $asmPath
    $org = 0x0100
    $labels = @{}

    for ($pass = 1; $pass -le 2; $pass++) {
        $buf = New-Object System.Collections.Generic.List[byte]
        $emit = { param([byte[]]$b) $buf.AddRange($b) }
        $emit16 = { param([int]$v) $buf.Add([byte]($v -band 0xFF)); $buf.Add([byte](($v -shr 8) -band 0xFF)) }
        $lineNo = 0

        :lineLoop foreach ($raw in $lines) {
            $lineNo++
            # Strip ; comment outside single quotes
            $inQ = $false; $cut = $raw.Length
            for ($k = 0; $k -lt $raw.Length; $k++) {
                if ($raw[$k] -eq "'") { $inQ = -not $inQ }
                elseif (-not $inQ -and $raw[$k] -eq ';') { $cut = $k; break }
            }
            $line = $raw.Substring(0, $cut).Trim()
            if ($line.Length -eq 0) { continue }

            # Label with colon
            if ($line -match '^([A-Za-z_][A-Za-z0-9_]*):(.*)$') {
                $labels[$Matches[1]] = $org + $buf.Count
                $line = $Matches[2].Trim()
                if ($line.Length -eq 0) { continue }
            }
            # Data label without colon: name db ...
            if ($line -match '^([A-Za-z_][A-Za-z0-9_]*)\s+db\s+(.+)$') {
                $labels[$Matches[1]] = $org + $buf.Count
                & $emit (Parse-DbArgs $Matches[2])
                continue
            }
            if ($line -match '^db\s+(.+)$') {
                & $emit (Parse-DbArgs $Matches[1])
                continue
            }
            if ($line -match '^bits\s+16$' -or $line -match '^org\s+100h$') { continue }

            $parts = $line -split '\s+', 2
            $op = $parts[0].ToLower()
            $argStr = if ($parts.Count -gt 1) { $parts[1].Trim() } else { "" }

            switch ($op) {
                'cld'   { & $emit @(0xFC); continue lineLoop }
                'cli'   { & $emit @(0xFA); continue lineLoop }
                'sti'   { & $emit @(0xFB); continue lineLoop }
                'ret'   { & $emit @(0xC3); continue lineLoop }
                'stosb' { & $emit @(0xAA); continue lineLoop }
                'lodsb' { & $emit @(0xAC); continue lineLoop }
                'push'  { & $emit @([byte](0x50 + $r16Map[$argStr.ToLower()])); continue lineLoop }
                'pop'   { & $emit @([byte](0x58 + $r16Map[$argStr.ToLower()])); continue lineLoop }
                'inc'   {
                    $r = $argStr.ToLower()
                    if ($r16Map.ContainsKey($r)) { & $emit @([byte](0x40 + $r16Map[$r])) }
                    elseif ($r8Map.ContainsKey($r)) { & $emit @(0xFE, [byte](0xC0 + $r8Map[$r])) }
                    else { throw "Line $lineNo : unsupported inc $argStr" }
                    continue lineLoop
                }
                'dec'   {
                    $r = $argStr.ToLower()
                    if ($r16Map.ContainsKey($r)) { & $emit @([byte](0x48 + $r16Map[$r])) }
                    elseif ($r8Map.ContainsKey($r)) { & $emit @(0xFE, [byte](0xC8 + $r8Map[$r])) }
                    else { throw "Line $lineNo : unsupported dec $argStr" }
                    continue lineLoop
                }
                'int'   { & $emit @(0xCD, [byte](Parse-Imm $argStr $labels $pass)); continue lineLoop }
                'call'  {
                    $target = Parse-Imm $argStr $labels $pass
                    $disp = $target - ($org + $buf.Count + 3)
                    & $emit @(0xE8); & $emit16 $disp; continue lineLoop
                }
                'jmp'   {
                    if ($argStr -match '^short\s+(.+)$') {
                        $target = Parse-Imm $Matches[1] $labels $pass
                        $disp = if ($pass -eq 1) { 0 } else { $target - ($org + $buf.Count + 2) }
                        if ($disp -lt -128 -or $disp -gt 127) { throw "Line $lineNo : jmp short out of range ($disp)" }
                        & $emit @(0xEB, [byte]($disp -band 0xFF))
                    } else {
                        $target = Parse-Imm $argStr $labels $pass
                        $disp = $target - ($org + $buf.Count + 3)
                        & $emit @(0xE9); & $emit16 $disp
                    }
                    continue lineLoop
                }
                default {
                    if ($jccMap.ContainsKey($op)) {
                        $target = Parse-Imm $argStr $labels $pass
                        $disp = if ($pass -eq 1) { 0 } else { $target - ($org + $buf.Count + 2) }
                        if ($disp -lt -128 -or $disp -gt 127) { throw "Line $lineNo : $op out of rel8 range ($disp) to $argStr" }
                        & $emit @([byte]$jccMap[$op], [byte]($disp -band 0xFF))
                        continue lineLoop
                    }
                }
            }

            # Two-operand instructions (split on first comma outside quotes)
            $inQ = $false; $comma = -1
            for ($k = 0; $k -lt $argStr.Length; $k++) {
                if ($argStr[$k] -eq "'") { $inQ = -not $inQ }
                elseif (-not $inQ -and $argStr[$k] -eq ',') { $comma = $k; break }
            }
            if ($comma -lt 0) { throw "Line $lineNo : unsupported instruction '$line'" }
            $dst = $argStr.Substring(0, $comma).Trim()
            $src = $argStr.Substring($comma + 1).Trim()
            $dl = $dst.ToLower(); $sl = $src.ToLower()

            switch ($op) {
                'mov' {
                    if ($r16Map.ContainsKey($dl) -and $r16Map.ContainsKey($sl)) {
                        & $emit @(0x89, [byte](0xC0 + $r16Map[$sl]*8 + $r16Map[$dl]))
                    } elseif ($r16Map.ContainsKey($dl)) {
                        $v = Parse-Imm $src $labels $pass
                        & $emit @([byte](0xB8 + $r16Map[$dl])); & $emit16 $v
                    } elseif ($r8Map.ContainsKey($dl) -and $r8Map.ContainsKey($sl)) {
                        & $emit @(0x88, [byte](0xC0 + $r8Map[$sl]*8 + $r8Map[$dl]))
                    } elseif ($r8Map.ContainsKey($dl) -and $src -match '^\[(si|di|bx)\]$') {
                        & $emit @(0x8A, [byte]($r8Map[$dl]*8 + $rmBase[$Matches[1].ToLower()]))
                    } elseif ($r8Map.ContainsKey($dl) -and $src -match '^\[(si|di|bx)\+([0-9]+)\]$') {
                        & $emit @(0x8A, [byte](0x40 + $r8Map[$dl]*8 + $rmBase[$Matches[1].ToLower()]), [byte][int]$Matches[2])
                    } elseif ($r8Map.ContainsKey($dl) -and $src -match '^\[(.+)\]$') {
                        $a = Parse-Imm $Matches[1] $labels $pass
                        if ($dl -eq 'al') { & $emit @(0xA0); & $emit16 $a }
                        else { & $emit @(0x8A, [byte](0x06 + $r8Map[$dl]*8)); & $emit16 $a }
                    } elseif ($r8Map.ContainsKey($dl)) {
                        & $emit @([byte](0xB0 + $r8Map[$dl]), [byte]((Parse-Imm $src $labels $pass) -band 0xFF))
                    } elseif ($dst -match '^\[(si|di|bx)\+([0-9]+)\]$' -and $r8Map.ContainsKey($sl)) {
                        & $emit @(0x88, [byte](0x40 + $r8Map[$sl]*8 + $rmBase[$Matches[1].ToLower()]), [byte][int]$Matches[2])
                    } elseif ($dst -match '^byte\s+\[(.+)\]$') {
                        $a = Parse-Imm $Matches[1] $labels $pass
                        $v = Parse-Imm $src $labels $pass
                        & $emit @(0xC6, 0x06); & $emit16 $a; & $emit @([byte]($v -band 0xFF))
                    } elseif ($dst -match '^\[(.+)\]$' -and $r8Map.ContainsKey($sl)) {
                        $a = Parse-Imm $Matches[1] $labels $pass
                        if ($sl -eq 'al') { & $emit @(0xA2); & $emit16 $a }
                        else { & $emit @(0x88, [byte](0x06 + $r8Map[$sl]*8)); & $emit16 $a }
                    } else { throw "Line $lineNo : unsupported mov $dst, $src" }
                }
                'xor' {
                    if ($r16Map.ContainsKey($dl) -and $r16Map.ContainsKey($sl)) { & $emit @(0x31, [byte](0xC0 + $r16Map[$sl]*8 + $r16Map[$dl])) }
                    elseif ($r8Map.ContainsKey($dl) -and $r8Map.ContainsKey($sl)) { & $emit @(0x30, [byte](0xC0 + $r8Map[$sl]*8 + $r8Map[$dl])) }
                    else { throw "Line $lineNo : unsupported xor" }
                }
                'add' {
                    if ($r16Map.ContainsKey($dl) -and $r16Map.ContainsKey($sl)) { & $emit @(0x01, [byte](0xC0 + $r16Map[$sl]*8 + $r16Map[$dl])) }
                    elseif ($r16Map.ContainsKey($dl)) { & $emit @(0x83, [byte](0xC0 + $r16Map[$dl]), [byte](Parse-Imm $src $labels $pass)) }
                    elseif ($dl -eq 'al') { & $emit @(0x04, [byte](Parse-Imm $src $labels $pass)) }
                    else { throw "Line $lineNo : unsupported add" }
                }
                'sub' {
                    if ($dl -eq 'al') { & $emit @(0x2C, [byte](Parse-Imm $src $labels $pass)) }
                    else { throw "Line $lineNo : unsupported sub" }
                }
                'and' {
                    if ($dl -eq 'al' -and $r8Map.ContainsKey($sl)) { & $emit @(0x20, [byte](0xC0 + $r8Map[$sl]*8)) }
                    elseif ($dl -eq 'al') { & $emit @(0x24, [byte](Parse-Imm $src $labels $pass)) }
                    else { throw "Line $lineNo : unsupported and" }
                }
                'or' {
                    if ($dl -eq 'al' -and $r8Map.ContainsKey($sl)) { & $emit @(0x08, [byte](0xC0 + $r8Map[$sl]*8)) }
                    elseif ($dl -eq 'al') { & $emit @(0x0C, [byte](Parse-Imm $src $labels $pass)) }
                    else { throw "Line $lineNo : unsupported or" }
                }
                'cmp' {
                    if ($r16Map.ContainsKey($dl)) {
                        & $emit @(0x83, [byte](0xF8 + $r16Map[$dl]), [byte](Parse-Imm $src $labels $pass))
                    } elseif ($dst -match '^byte\s+\[(.+)\]$') {
                        $a = Parse-Imm $Matches[1] $labels $pass
                        & $emit @(0x80, 0x3E); & $emit16 $a; & $emit @([byte](Parse-Imm $src $labels $pass))
                    } elseif ($r8Map.ContainsKey($dl) -and $src -match '^\[(si|di|bx)\]$') {
                        & $emit @(0x3A, [byte]($r8Map[$dl]*8 + $rmBase[$Matches[1].ToLower()]))
                    } elseif ($r8Map.ContainsKey($dl) -and $src -match '^\[(.+)\]$') {
                        $a = Parse-Imm $Matches[1] $labels $pass
                        & $emit @(0x3A, [byte](0x06 + $r8Map[$dl]*8)); & $emit16 $a
                    } elseif ($dl -eq 'al') {
                        & $emit @(0x3C, [byte](Parse-Imm $src $labels $pass))
                    } elseif ($r8Map.ContainsKey($dl)) {
                        & $emit @(0x80, [byte](0xF8 + $r8Map[$dl]), [byte](Parse-Imm $src $labels $pass))
                    } else { throw "Line $lineNo : unsupported cmp $dst, $src" }
                }
                'test' {
                    if ($dst -match '^byte\s+\[(.+)\]$') {
                        $a = Parse-Imm $Matches[1] $labels $pass
                        & $emit @(0xF6, 0x06); & $emit16 $a; & $emit @([byte](Parse-Imm $src $labels $pass))
                    } else { throw "Line $lineNo : unsupported test" }
                }
                'shr' {
                    if ($dl -eq 'al' -and $sl -eq 'cl') { & $emit @(0xD2, 0xE8) }
                    else { throw "Line $lineNo : unsupported shr" }
                }
                'in'  {
                    if ($dl -eq 'al' -and $sl -eq 'dx') { & $emit @(0xEC) }
                    else { & $emit @(0xE4, [byte](Parse-Imm $src $labels $pass)) }
                }
                'out' {
                    if ($dl -eq 'dx' -and $sl -eq 'al') { & $emit @(0xEE) }
                    else { & $emit @(0xE6, [byte](Parse-Imm $dst $labels $pass)) }
                }
                default { throw "Line $lineNo : unsupported op '$op'" }
            }
        }
    }
    return $buf.ToArray()
}

$asmPath = Join-Path $PSScriptRoot 'acctune.asm'
$outPath = Join-Path $PSScriptRoot 'ACCTUNE.COM'
$bytes = Assemble-Asm $asmPath
[System.IO.File]::WriteAllBytes($outPath, $bytes)

# ---- 8086 Emulator Test Harness ----
$hwRegs = @{ 0x04 = 0x54; 0x05 = 0x18; 0x0B = 0x05; 0x18 = 0x00; 0x19 = 0x00 }
$vgaPresent = $true
$nonCirrusMode = 'unmapped' # 'unmapped' (reads FFh) or 'scratch' (generic R/W SR06)
$nonCirrusSr06Init = 0x5A
$nonCirrusSr06 = $nonCirrusSr06Init
$vgaIdxInit = 0x03
$vgaIdx = $vgaIdxInit
$vgaRegs = @{ 0x06 = 0x12; 0x0F = 0x10; 0x16 = 0xD8; 0x17 = 0x31; 0x1F = 0x1C }

function Run-Emu([string]$cmdTail) {
    $mem = New-Object byte[] 0x10000
    $tb = [System.Text.Encoding]::ASCII.GetBytes($cmdTail)
    $mem[0x80] = [byte]$tb.Length
    for ($i = 0; $i -lt $tb.Length; $i++) { $mem[0x81 + $i] = $tb[$i] }
    $mem[0x81 + $tb.Length] = 0x0D
    [Array]::Copy($bytes, 0, $mem, 0x100, $bytes.Length)

    $r = @(0,0,0,0, 0xFFFE, 0, 0, 0) # ax,cx,dx,bx,sp,bp,si,di
    $ip = 0x100; $zf=$false; $cf=$false; $df=$true; $iflag=$true
    $idx = 0; $ioBad = $false; $writes = 0; $writeOrder = New-Object System.Collections.Generic.List[byte]
    $vgaTouches = 0; $vgaWrites = 0; $vgaUnlockedAccess = $false; $out = ""; $rc = -1
    $script:vgaIdx = $script:vgaIdxInit
    $script:nonCirrusSr06 = $script:nonCirrusSr06Init

    $getR8 = { param($n) if ($n -lt 4) { $r[$n] -band 0xFF } else { ($r[$n-4] -shr 8) -band 0xFF } }
    $setR8 = { param($n,$v) $v = $v -band 0xFF; if ($n -lt 4) { $r[$n] = ($r[$n] -band 0xFF00) -bor $v } else { $r[$n-4] = ($r[$n-4] -band 0x00FF) -bor ($v -shl 8) } }
    $rd16 = { param($a) [int]$mem[$a] + (([int]$mem[$a+1]) -shl 8) }
    $s8 = { param([byte]$b) if ($b -ge 128) { $b - 256 } else { [int]$b } }
    $s16 = { param([int]$w) if ($w -ge 32768) { $w - 65536 } else { $w } }
    $eaOf = {
        param($mod, $rm)
        if ($mod -eq 0 -and $rm -eq 6) { $a = & $rd16 $script:ip; $script:ip += 2; return $a }
        $base = switch ($rm) { 4 { $r[6] } 5 { $r[7] } 7 { $r[3] } default { throw "bad rm $rm" } }
        if ($mod -eq 1) { $d = & $s8 $mem[$script:ip++]; return ($base + $d) -band 0xFFFF }
        return $base
    }
    $script:ip = $ip

    for ($step = 0; $step -lt 20000; $step++) {
        $op = $mem[$script:ip++]
        if ($op -ge 0x50 -and $op -le 0x57) {
            $v = $r[$op - 0x50]; $r[4] = ($r[4] - 2) -band 0xFFFF
            $mem[$r[4]] = [byte]($v -band 0xFF); $mem[$r[4]+1] = [byte](($v -shr 8) -band 0xFF); continue
        }
        if ($op -ge 0x58 -and $op -le 0x5F) {
            $r[$op - 0x58] = & $rd16 $r[4]; $r[4] = ($r[4] + 2) -band 0xFFFF; continue
        }
        if ($op -ge 0x40 -and $op -le 0x47) { $n = $op - 0x40; $r[$n] = ($r[$n] + 1) -band 0xFFFF; $zf = ($r[$n] -eq 0); continue }
        if ($op -ge 0x48 -and $op -le 0x4F) { $n = $op - 0x48; $r[$n] = ($r[$n] - 1) -band 0xFFFF; $zf = ($r[$n] -eq 0); continue }
        if ($op -ge 0xB0 -and $op -le 0xB7) { & $setR8 ($op - 0xB0) $mem[$script:ip++]; continue }
        if ($op -ge 0xB8 -and $op -le 0xBF) { $r[$op - 0xB8] = & $rd16 $script:ip; $script:ip += 2; continue }

        switch ($op) {
            0xFC { $df = $false }
            0xFA { $iflag = $false }
            0xFB { $iflag = $true }
            0xAA { $mem[$r[7]] = [byte]($r[0] -band 0xFF); $r[7] = ($r[7] + $(if ($df){-1}else{1})) -band 0xFFFF }
            0xAC { & $setR8 0 $mem[$r[6]]; $r[6] = ($r[6] + $(if ($df){-1}else{1})) -band 0xFFFF }
            0xC3 { $script:ip = & $rd16 $r[4]; $r[4] = ($r[4] + 2) -band 0xFFFF }
            0xE8 {
                $d = & $s16 (& $rd16 $script:ip); $script:ip += 2
                $r[4] = ($r[4] - 2) -band 0xFFFF
                $mem[$r[4]] = [byte]($script:ip -band 0xFF); $mem[$r[4]+1] = [byte](($script:ip -shr 8) -band 0xFF)
                $script:ip = ($script:ip + $d) -band 0xFFFF
            }
            0xEB { $d = & $s8 $mem[$script:ip++]; $script:ip = ($script:ip + $d) -band 0xFFFF }
            0xE9 { $d = & $s16 (& $rd16 $script:ip); $script:ip = ($script:ip + 2 + $d) -band 0xFFFF }
            0x74 { $d = & $s8 $mem[$script:ip++]; if ($zf) { $script:ip = ($script:ip + $d) -band 0xFFFF } }
            0x75 { $d = & $s8 $mem[$script:ip++]; if (-not $zf) { $script:ip = ($script:ip + $d) -band 0xFFFF } }
            0x72 { $d = & $s8 $mem[$script:ip++]; if ($cf) { $script:ip = ($script:ip + $d) -band 0xFFFF } }
            0x73 { $d = & $s8 $mem[$script:ip++]; if (-not $cf) { $script:ip = ($script:ip + $d) -band 0xFFFF } }
            0x76 { $d = & $s8 $mem[$script:ip++]; if ($cf -or $zf) { $script:ip = ($script:ip + $d) -band 0xFFFF } }
            0x77 { $d = & $s8 $mem[$script:ip++]; if (-not $cf -and -not $zf) { $script:ip = ($script:ip + $d) -band 0xFFFF } }
            0xA0 { $a = & $rd16 $script:ip; $script:ip += 2; & $setR8 0 $mem[$a] }
            0xA2 { $a = & $rd16 $script:ip; $script:ip += 2; $mem[$a] = [byte]($r[0] -band 0xFF) }
            0x88 {
                $m = $mem[$script:ip++]; $mod = ($m -shr 6) -band 3; $reg = ($m -shr 3) -band 7; $rm = $m -band 7
                if ($mod -eq 3) { & $setR8 $rm (& $getR8 $reg) }
                else { $a = & $eaOf $mod $rm; $mem[$a] = [byte](& $getR8 $reg) }
            }
            0x89 {
                $m = $mem[$script:ip++]; $mod = ($m -shr 6) -band 3; $reg = ($m -shr 3) -band 7; $rm = $m -band 7
                if ($mod -ne 3) { throw "89 mod" }; $r[$rm] = $r[$reg]
            }
            0x8A {
                $m = $mem[$script:ip++]; $mod = ($m -shr 6) -band 3; $reg = ($m -shr 3) -band 7; $rm = $m -band 7
                $a = & $eaOf $mod $rm; & $setR8 $reg $mem[$a]
            }
            0xC6 {
                $m = $mem[$script:ip++]; if ($m -ne 0x06) { throw "C6" }
                $a = & $rd16 $script:ip; $script:ip += 2; $mem[$a] = $mem[$script:ip++]
            }
            0x30 {
                $m = $mem[$script:ip++]; $reg = ($m -shr 3) -band 7; $rm = $m -band 7
                $v = (& $getR8 $rm) -bxor (& $getR8 $reg); & $setR8 $rm $v; $zf = ($v -eq 0); $cf = $false
            }
            0x31 {
                $m = $mem[$script:ip++]; $reg = ($m -shr 3) -band 7; $rm = $m -band 7
                $r[$rm] = $r[$rm] -bxor $r[$reg]; $zf = ($r[$rm] -eq 0); $cf = $false
            }
            0x01 {
                $m = $mem[$script:ip++]; $reg = ($m -shr 3) -band 7; $rm = $m -band 7
                $sum = $r[$rm] + $r[$reg]; $cf = ($sum -gt 0xFFFF); $r[$rm] = $sum -band 0xFFFF; $zf = ($r[$rm] -eq 0)
            }
            0x04 { $sum = ($r[0] -band 0xFF) + [int]$mem[$script:ip++]; $cf = ($sum -gt 0xFF); & $setR8 0 $sum; $zf = (($sum -band 0xFF) -eq 0) }
            0x2C { $a = $r[0] -band 0xFF; $b = [int]$mem[$script:ip++]; $cf = ($a -lt $b); $d = ($a - $b) -band 0xFF; & $setR8 0 $d; $zf = ($d -eq 0) }
            0x24 { $v = ($r[0] -band 0xFF) -band [int]$mem[$script:ip++]; & $setR8 0 $v; $zf = ($v -eq 0); $cf = $false }
            0x0C { $v = ($r[0] -band 0xFF) -bor [int]$mem[$script:ip++]; & $setR8 0 $v; $zf = ($v -eq 0); $cf = $false }
            0x20 { $m = $mem[$script:ip++]; $reg = ($m -shr 3) -band 7; $rm = $m -band 7; $v = (& $getR8 $rm) -band (& $getR8 $reg); & $setR8 $rm $v; $zf = ($v -eq 0); $cf = $false }
            0x08 { $m = $mem[$script:ip++]; $reg = ($m -shr 3) -band 7; $rm = $m -band 7; $v = (& $getR8 $rm) -bor (& $getR8 $reg); & $setR8 $rm $v; $zf = ($v -eq 0); $cf = $false }
            0x3C { $a = $r[0] -band 0xFF; $b = [int]$mem[$script:ip++]; $cf = ($a -lt $b); $zf = ($a -eq $b) }
            0x3A {
                $m = $mem[$script:ip++]; $mod = ($m -shr 6) -band 3; $reg = ($m -shr 3) -band 7; $rm = $m -band 7
                $a = & $eaOf $mod $rm; $x = & $getR8 $reg; $y = [int]$mem[$a]; $cf = ($x -lt $y); $zf = ($x -eq $y)
            }
            0x80 {
                $m = $mem[$script:ip++]; $mod = ($m -shr 6) -band 3; $sub = ($m -shr 3) -band 7; $rm = $m -band 7
                if ($sub -ne 7) { throw "80 sub $sub" }
                if ($mod -eq 3) { $x = & $getR8 $rm } else { $a = & $eaOf $mod $rm; $x = [int]$mem[$a] }
                $y = [int]$mem[$script:ip++]; $cf = ($x -lt $y); $zf = ($x -eq $y)
            }
            0x83 {
                $m = $mem[$script:ip++]; $sub = ($m -shr 3) -band 7; $rm = $m -band 7; $imm = & $s8 $mem[$script:ip++]
                if ($sub -eq 0) { $sum = $r[$rm] + $imm; $r[$rm] = $sum -band 0xFFFF; $zf = ($r[$rm] -eq 0) }
                elseif ($sub -eq 7) { $uimm = $imm -band 0xFFFF; $cf = ($r[$rm] -lt $uimm); $zf = ($r[$rm] -eq $uimm) }
                else { throw "83 sub $sub" }
            }
            0xF6 {
                $m = $mem[$script:ip++]; if ($m -ne 0x06) { throw "F6" }
                $a = & $rd16 $script:ip; $script:ip += 2; $imm = [int]$mem[$script:ip++]
                $zf = (([int]$mem[$a] -band $imm) -eq 0); $cf = $false
            }
            0xFE {
                $m = $mem[$script:ip++]; $sub = ($m -shr 3) -band 7; $rm = $m -band 7
                $v = & $getR8 $rm
                if ($sub -eq 0) { $v = ($v + 1) -band 0xFF } elseif ($sub -eq 1) { $v = ($v - 1) -band 0xFF } else { throw "FE" }
                & $setR8 $rm $v; $zf = ($v -eq 0)
            }
            0xD2 {
                $m = $mem[$script:ip++]; if ($m -ne 0xE8) { throw "D2" }
                $c = $r[1] -band 0xFF; $v = ($r[0] -band 0xFF) -shr $c; & $setR8 0 $v; $zf = ($v -eq 0)
            }
            0xE6 {
                $port = $mem[$script:ip++]; $al = $r[0] -band 0xFF
                if ($iflag) { $ioBad = $true }
                if ($port -eq 0xF2) { $idx = $al }
                elseif ($port -eq 0xF3) { $hwRegs[$idx] = $al; $writes++; $writeOrder.Add([byte]$idx) }
                elseif ($port -ne 0xED) { throw "OUT $port" }
            }
            0xE4 {
                if ($iflag) { $ioBad = $true }
                if ($mem[$script:ip++] -ne 0xF3) { throw "IN port" }
                & $setR8 0 $hwRegs[$idx]
            }
            0xEE {
                $port = $r[2]; $al = $r[0] -band 0xFF
                if ($iflag) { $ioBad = $true }
                if ($port -eq 0x3C4) {
                    $script:vgaIdx = $al; $vgaTouches++
                } elseif ($port -eq 0x3C5) {
                    $vgaTouches++
                    if ($script:vgaIdx -eq 0x06) {
                        if ($script:vgaPresent) { $script:vgaRegs[0x06] = $(if (($al -band 0x17) -eq 0x12) { 0x12 } else { 0x0F }) }
                        elseif ($script:nonCirrusMode -eq 'scratch') { $script:nonCirrusSr06 = $al }
                    } else {
                        if (-not $script:vgaPresent -or $script:vgaRegs[0x06] -ne 0x12) { $vgaUnlockedAccess = $true }
                        else { $script:vgaRegs[$script:vgaIdx] = $al; $vgaWrites++ }
                    }
                } else { throw ("OUT DX port {0:X4}" -f $port) }
            }
            0xEC {
                $port = $r[2]
                if ($iflag) { $ioBad = $true }
                if ($port -eq 0x3C4) {
                    $vgaTouches++; & $setR8 0 $script:vgaIdx
                } elseif ($port -eq 0x3C5) {
                    $vgaTouches++
                    if (-not $script:vgaPresent) {
                        if ($script:vgaIdx -eq 0x06 -and $script:nonCirrusMode -eq 'scratch') { & $setR8 0 $script:nonCirrusSr06 }
                        else { & $setR8 0 0xFF }
                    }
                    elseif ($script:vgaIdx -eq 0x06) { & $setR8 0 $script:vgaRegs[0x06] }
                    elseif ($script:vgaRegs[0x06] -ne 0x12) { $vgaUnlockedAccess = $true; & $setR8 0 0xFF }
                    else { & $setR8 0 $script:vgaRegs[$script:vgaIdx] }
                } else { throw ("IN DX port {0:X4}" -f $port) }
            }
            0xCD {
                if ($mem[$script:ip++] -ne 0x21) { throw "INT" }
                $ah = ($r[0] -shr 8) -band 0xFF
                if ($ah -eq 0x09) { $p = $r[2]; while ($mem[$p] -ne 0x24) { $out += [char]$mem[$p++] } }
                elseif ($ah -eq 0x02) { $out += [char]($r[2] -band 0xFF) }
                elseif ($ah -eq 0x4C) { $rc = $r[0] -band 0xFF; break }
                else { throw "INT 21 AH=$ah" }
            }
            default { throw ("Unknown opcode {0:X2} at {1:X4}" -f $op, ($script:ip - 1)) }
        }
        if ($rc -ge 0) { break }
    }
    $sr06Ok = if ($script:vgaPresent) { ($vgaTouches -eq 0) -or ($script:vgaRegs[0x06] -eq 0x12) } else { $script:nonCirrusSr06 -eq $script:nonCirrusSr06Init }
    $vgaClean = ($script:vgaIdx -eq $script:vgaIdxInit) -and (-not $vgaUnlockedAccess) -and $sr06Ok
    return @{ Rc=$rc; Out=$out; Writes=$writes; Order=$writeOrder.ToArray(); VgaTouches=$vgaTouches; VgaWrites=$vgaWrites; Safe=($iflag -and -not $ioBad -and $vgaClean) }
}

$testCount = 0
function Assert-Run([string]$cmd, [int]$expRc, [int]$expWrites, [byte]$e04, [byte]$e05, [byte]$e0b, [byte]$e18, [byte]$e19, [string]$mustContain, [int]$expVgaWrites = 0, [int]$expVgaTouches = -1) {
    $script:testCount++
    $res = Run-Emu $cmd
    if (-not $res.Safe) { throw "Safety (IF/SR06-lock/3C4-restore) failed on '$cmd'" }
    if ($res.Rc -ne $expRc) { throw "RC mismatch on '$cmd': got $($res.Rc) expected $expRc" }
    if ($res.Writes -ne $expWrites) { throw "Write count mismatch on '$cmd': got $($res.Writes) expected $expWrites" }
    if ($res.VgaWrites -ne $expVgaWrites) { throw "VGA write count mismatch on '$cmd': got $($res.VgaWrites) expected $expVgaWrites" }
    if ($expVgaTouches -ge 0 -and $res.VgaTouches -ne $expVgaTouches) { throw "VGA touch count mismatch on '$cmd': got $($res.VgaTouches) expected $expVgaTouches" }
    if ($hwRegs[4] -ne $e04 -or $hwRegs[5] -ne $e05 -or $hwRegs[0xB] -ne $e0b -or $hwRegs[0x18] -ne $e18 -or $hwRegs[0x19] -ne $e19) {
        throw ("Reg mismatch on '{0}': got 04={1:X2} 05={2:X2} 0B={3:X2} 18={4:X2} 19={5:X2}" -f $cmd, $hwRegs[4], $hwRegs[5], $hwRegs[0xB], $hwRegs[0x18], $hwRegs[0x19])
    }
    if ($mustContain -and -not $res.Out.Contains($mustContain)) {
        throw "Output mismatch on '$cmd': missing '$mustContain' in:`n$($res.Out)"
    }
    return $res
}

# Pure ACC tests must never touch 3C4h/3C5h ($expVgaTouches = 0)
$sample0 = (Assert-Run ""                0 0 0x54 0x18 0x05 0x00 0x00 "State: PW=OFF RF=/2 BR=OFF AT=ON W486=0WS CASW=2T PWWS=1WS L2=OFF" 0 0).Out
$null    = Assert-Run " /?"              0 0 0x54 0x18 0x05 0x00 0x00 "Flags (opt-in" 0 0
$null    = Assert-Run " /PW /?"          0 0 0x54 0x18 0x05 0x00 0x00 "Flags (opt-in" 0 0
$null    = Assert-Run " /V /?"           0 0 0x54 0x18 0x05 0x00 0x00 "Flags (opt-in" 0 0
$null    = Assert-Run " /BOGUS"          1 0 0x54 0x18 0x05 0x00 0x00 "Unknown flag" 0 0
$null    = Assert-Run " /PW /BOGUS"      1 0 0x54 0x18 0x05 0x00 0x00 "Unknown flag" 0 0
$null    = Assert-Run " /BR9"            1 0 0x54 0x18 0x05 0x00 0x00 "Unknown flag" 0 0
$null    = Assert-Run " /VM70"           1 0 0x54 0x18 0x05 0x00 0x00 "Unknown flag" 0 0
$null    = Assert-Run " /"               1 0 0x54 0x18 0x05 0x00 0x00 "Unknown flag" 0 0
$null    = Assert-Run " /r"              0 1 0x54 0x19 0x05 0x00 0x00 "State: PW=OFF RF=/4 BR=OFF AT=ON W486=0WS CASW=2T PWWS=1WS L2=OFF" 0 0
$null    = Assert-Run " /r8"             0 1 0x54 0x1A 0x05 0x00 0x00 "State: PW=OFF RF=/8 BR=OFF AT=ON W486=0WS CASW=2T PWWS=1WS L2=OFF" 0 0
$null    = Assert-Run " /r16"            0 1 0x54 0x1B 0x05 0x00 0x00 "State: PW=OFF RF=/16 BR=OFF AT=ON W486=0WS CASW=2T PWWS=1WS L2=OFF" 0 0
$null    = Assert-Run " /r2"             0 1 0x54 0x18 0x05 0x00 0x00 "State: PW=OFF RF=/2 BR=OFF AT=ON W486=0WS CASW=2T PWWS=1WS L2=OFF" 0 0
$null    = Assert-Run " /r4 /pw"         0 2 0xD4 0x19 0x05 0x00 0x00 "State: PW=ON RF=/4 BR=OFF AT=ON W486=0WS CASW=2T PWWS=1WS L2=OFF" 0 0
$null    = Assert-Run " /pw-"            0 1 0x54 0x19 0x05 0x00 0x00 "State: PW=OFF RF=/4 BR=OFF AT=ON W486=0WS CASW=2T PWWS=1WS L2=OFF" 0 0
$null    = Assert-Run " /pw+/r-/w0-"     0 2 0x94 0x18 0x05 0x00 0x00 "State: PW=ON RF=/2 BR=OFF AT=ON W486=STD CASW=2T PWWS=1WS L2=OFF" 0 0
$null    = Assert-Run " /w0+ /c1+ /p0+"  0 3 0xD4 0x18 0x04 0x10 0x00 "State: PW=ON RF=/2 BR=OFF AT=ON W486=0WS CASW=1T PWWS=0WS L2=OFF" 0 0
$null    = Assert-Run " /c1- /p0-"       0 2 0xD4 0x18 0x05 0x00 0x00 "State: PW=ON RF=/2 BR=OFF AT=ON W486=0WS CASW=2T PWWS=1WS L2=OFF" 0 0
$null    = Assert-Run " /at-"            0 1 0xD4 0x18 0x05 0x01 0x00 "State: PW=ON RF=/2 BR=OFF AT=OFF W486=0WS CASW=2T PWWS=1WS L2=OFF" 0 0
$rBr     = Assert-Run " /br"             0 2 0xD4 0x18 0x05 0x03 0x03 "State: PW=ON RF=/2 BR=4 AT=OFF W486=0WS CASW=2T PWWS=1WS L2=OFF" 0 0
if ($rBr.Order[0] -ne 0x19 -or $rBr.Order[1] -ne 0x18) { throw "Expected 19h written before 18h on /br, got $($rBr.Order -join ',')" }
$null    = Assert-Run " /br8 /r8"        0 3 0xD4 0x1A 0x05 0x03 0x07 "State: PW=ON RF=/8 BR=8 AT=OFF W486=0WS CASW=2T PWWS=1WS L2=OFF" 0 0
$null    = Assert-Run " /br1 /at+"       0 2 0xD4 0x1A 0x05 0x02 0x00 "State: PW=ON RF=/8 BR=1 AT=ON W486=0WS CASW=2T PWWS=1WS L2=OFF" 0 0
$null    = Assert-Run " /br-"            0 2 0xD4 0x1A 0x05 0x00 0x00 "State: PW=ON RF=/8 BR=OFF AT=ON W486=0WS CASW=2T PWWS=1WS L2=OFF" 0 0
$null    = Assert-Run " /off"            0 5 0x54 0x18 0x05 0x00 0x00 "VGA:   SR0F=10 SR16=D8 SR17=31 SR1F=1C VIO=2T" 2

# Cirrus VGA read-only + tuning + SR06=12h SVGA-unlock + bit-preservation + non-Cirrus safety tests
$vgaRegs[0x06] = 0x0F # Simulate SR06 previously locked; /v must re-unlock SR06=12h for VESA/SVGA BIOS
$null    = Assert-Run " /v"              0 0 0x54 0x18 0x05 0x00 0x00 "VGA:   SR0F=10 SR16=D8 SR17=31 SR1F=1C VIO=2T" 0
$null    = Assert-Run " /vio"            0 0 0x54 0x18 0x05 0x00 0x00 "VGA:   SR0F=10 SR16=18 SR17=31 SR1F=1C VIO=1T" 1
if ($vgaRegs[0x16] -ne 0x18 -or $vgaRegs[0x1F] -ne 0x1C) { throw "VGA reg mismatch after /vio" }
$null    = Assert-Run " /vm"             0 0 0x54 0x18 0x05 0x00 0x00 "VGA:   SR0F=10 SR16=18 SR17=31 SR1F=1E VIO=1T" 1
if ($vgaRegs[0x1F] -ne 0x1E) { throw "VGA SR1F mismatch after /vm" }
$null    = Assert-Run " /pw /r8 /br4 /at- /vio /vm57" 0 4 0xD4 0x1A 0x05 0x03 0x03 "VGA:   SR0F=10 SR16=18 SR17=31 SR1F=20 VIO=1T" 2
if ($vgaRegs[0x16] -ne 0x18 -or $vgaRegs[0x1F] -ne 0x20 -or $vgaRegs[0x06] -ne 0x12) { throw "VGA reg/SR06 mismatch after /vm57" }
$null    = Assert-Run " /vm61"           0 0 0xD4 0x1A 0x05 0x03 0x03 "VGA:   SR0F=10 SR16=18 SR17=31 SR1F=22 VIO=1T" 1
$null    = Assert-Run " /vm64"           0 0 0xD4 0x1A 0x05 0x03 0x03 "VGA:   SR0F=10 SR16=18 SR17=31 SR1F=24 VIO=1T" 1
$null    = Assert-Run " /vio- /vm-"      0 0 0xD4 0x1A 0x05 0x03 0x03 "VGA:   SR0F=10 SR16=D8 SR17=31 SR1F=1C VIO=2T" 2
# Verify SR16 b5:0 and SR1F b7:6 are preserved across /VIO /VM57 AND across /OFF
$vgaRegs[0x16] = 0xE5; $vgaRegs[0x1F] = 0x5C
$null    = Assert-Run " /vio /vm57"      0 0 0xD4 0x1A 0x05 0x03 0x03 "VGA:   SR0F=10 SR16=25 SR17=31 SR1F=60 VIO=1T" 2
$vgaRegs[0x06] = 0x0F # Also verify /0 unlocks SR06=12h while resetting both ACC and Cirrus VGA
$hwRegs[4] = 0x95; $hwRegs[5] = 0x1B; $hwRegs[0x18] = 0x13; $hwRegs[0x19] = 0xA7
$null    = Assert-Run " /0"              0 5 0x15 0x18 0x05 0x00 0xA0 "VGA:   SR0F=10 SR16=E5 SR17=31 SR1F=5C VIO=2T" 2
if ($vgaRegs[0x16] -ne 0xE5 -or $vgaRegs[0x1F] -ne 0x5C -or $vgaRegs[0x06] -ne 0x12) { throw "/0 failed to reset VGA regs cleanly" }
# Verify /OFF + /VM54 composes left-to-right
$null    = Assert-Run " /off /vm54"      0 5 0x15 0x18 0x05 0x00 0xA0 "VGA:   SR0F=10 SR16=E5 SR17=31 SR1F=5E VIO=2T" 2
# Verify non-Cirrus cards (both unmapped FFh and generic scratch SR06) abort RC=2 on explicit VGA flags,
# while /OFF still resets ACC cleanly with RC=0 and 0 VGA extension writes!
$vgaPresent = $false; $nonCirrusMode = 'unmapped'
$null    = Assert-Run " /pw /vio /vm57"  2 0 0x15 0x18 0x05 0x00 0xA0 "Cirrus CL-GD542x VGA not detected" 0
$nonCirrusMode = 'scratch'
$null    = Assert-Run " /off /vm54"      2 0 0x15 0x18 0x05 0x00 0xA0 "Cirrus CL-GD542x VGA not detected" 0
$hwRegs[4] = 0x95; $hwRegs[5] = 0x1B
$rOffNC  = Assert-Run " /off"            0 5 0x15 0x18 0x05 0x00 0xA0 "State: PW=OFF RF=/2 BR=OFF AT=ON W486=STD CASW=2T PWWS=1WS L2=ON" 0
if ($rOffNC.Out.Contains("VGA:")) { throw "/off printed VGA line when Cirrus absent" }
$vgaPresent = $true

$hash = (Get-FileHash $outPath -Algorithm SHA256).Hash
Write-Host "Built $outPath ($($bytes.Length) bytes), $testCount/$testCount emulation tests passed!"
Write-Host "SHA256: $hash"
Write-Host "--- Sample no-arg output ---"
Write-Host $sample0.TrimEnd()

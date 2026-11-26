; ACCTUNE.COM - Opt-in ACC Micro 2046 / 2168 / 2168GT Chipset Tuner for MS-DOS
;
; Usage:
;   ACCTUNE                 Read-only register status + help (no writes)
;   ACCTUNE /PW+  | /PW-    Posted Write ON/OFF (04h b7)
;   ACCTUNE /R+   | /R-     Slow DRAM Refresh ON/OFF (05h b1:0)
;   ACCTUNE /BR1..8 | /BR-  Burst Refresh ON (1-8, /BR=4) / OFF (18h b1, 19h b2:0)
;   ACCTUNE /AT-  | /AT+    AT Bus Refresh OFF/ON (18h b0: 1=disabled, 0=stock)
;   ACCTUNE /W0+  | /W0-    486 0-WS Mem Write ON/OFF (04h b6)
;   ACCTUNE /C1+  | /C1-    1T/2T CAS Write pulse (0Bh b1:0: 00=1T, 01=2T; exp.)
;   ACCTUNE /P0+  | /P0-    0-WS/1-WS Posted Write (18h b4; exp.)
;   ACCTUNE /OFF            Reset all tuned bits to safe stock (or /STOCK, /0)
;   (Shorthand without '+' enables the flag, e.g. ACCTUNE /PW /R /BR4 /AT-)
;
; Build with NASM:
;   nasm -f bin acctune.asm -o ACCTUNE.COM
; Or on Windows with zero external dependencies:
;   .\build.ps1

        bits 16
        org 100h

start:
        cld
        mov     si, 0081h
        xor     cx, cx
        mov     cl, [0080h]

; ---- Phase 1: Parse all CLI tokens before touching hardware ----
parse_loop:
        cmp     cx, 0
        je      parse_done

        ; Skip spaces, tabs, CR
        mov     al, [si]
        cmp     al, ' '
        je      skip_ws
        cmp     al, 09h
        je      skip_ws
        cmp     al, 0Dh
        je      parse_done

        ; Consume optional leading '/' or '-'
        cmp     al, '/'
        je      eat_prefix
        cmp     al, '-'
        je      eat_prefix
        jmp     short read_tok

skip_ws:
        inc     si
        dec     cx
        jmp     short parse_loop

eat_prefix:
        inc     si
        dec     cx
        cmp     cx, 0
        je      bad_flag

read_tok:
        mov     di, tok_buf
        xor     dl, dl              ; DL = token length

tok_char:
        cmp     cx, 0
        je      tok_end
        mov     al, [si]
        cmp     al, ' '
        je      tok_end
        cmp     al, 09h
        je      tok_end
        cmp     al, 0Dh
        je      tok_end
        cmp     al, '/'
        je      tok_end

        ; Uppercase 'a'..'z'
        cmp     al, 'a'
        jb      store_ch
        cmp     al, 'z'
        ja      store_ch
        sub     al, 20h

store_ch:
        cmp     dl, 7
        jae     bad_flag
        stosb
        inc     dl
        inc     si
        dec     cx
        jmp     short tok_char

tok_end:
        cmp     dl, 0
        je      bad_flag
        mov     [tok_len], dl

        ; Look up token in flag_tbl (preserve SI, CX)
        push    si
        push    cx
        call    match_flag
        pop     cx
        pop     si
        cmp     al, 0
        je      bad_flag
        jmp     short parse_loop

bad_flag:
        mov     dx, msg_bad
        call    print_str
        mov     dx, msg_help
        call    print_str
        mov     ax, 4C01h
        int     21h

; ---- Phase 2: Read-only help/status or apply pending masks ----
parse_done:
        mov     dx, msg_hdr
        call    print_str

        cmp     byte [want_help], 0
        jne     show_help
        cmp     byte [has_chg], 0
        je      show_help

        ; Apply only modified slots in pend_tbl (5 entries x 3 bytes; 19h before 18h)
        mov     si, pend_tbl
        mov     cx, 5
apply_loop:
        mov     al, [si]            ; reg index
        mov     bh, [si+1]          ; AND mask
        mov     bl, [si+2]          ; OR bits
        cmp     bh, 0FFh
        jne     do_rmw
        cmp     bl, 00h
        je      next_slot
do_rmw:
        push    si
        push    cx
        call    acc_rmw
        pop     cx
        pop     si
next_slot:
        add     si, 3
        dec     cx
        jne     apply_loop

        call    print_status
        mov     ax, 4C00h
        int     21h

show_help:
        call    print_status
        mov     dx, msg_help
        call    print_str
        mov     ax, 4C00h
        int     21h

; ---- match_flag: match [tok_buf]/[tok_len] in flag_tbl ----
; Returns AL = 1 if matched, 0 if unknown
match_flag:
        mov     bx, flag_tbl
mf_next:
        mov     al, [bx]            ; entry string length
        cmp     al, 0
        je      mf_fail
        inc     bx                  ; BX -> entry string
        xor     ah, ah
        mov     dx, ax              ; DX = entry len

        cmp     al, [tok_len]
        jne     mf_skip

        ; Compare DX bytes: [BX] vs [tok_buf]
        push    bx
        mov     si, bx
        mov     di, tok_buf
        mov     cx, dx
mf_cmp:
        mov     al, [si]
        cmp     al, [di]
        jne     mf_cmp_fail
        inc     si
        inc     di
        dec     cx
        jne     mf_cmp

        ; Matched! BX still saved on stack; SI points to (slot, keep, bits)
        pop     bx
        mov     al, [si]            ; slot
        mov     bh, [si+1]          ; keep_mask
        mov     bl, [si+2]          ; set_bits

        cmp     al, 0FDh
        je      mf_br
        cmp     al, 0FEh
        je      mf_help
        cmp     al, 0FFh
        je      mf_off

        call    stage_slot
        mov     al, 1
        ret

mf_cmp_fail:
        pop     bx
mf_skip:
        add     bx, dx
        add     bx, 3
        jmp     short mf_next

mf_fail:
        xor     al, al
        ret

mf_br:
        ; BH = 18h b1 (02h ON / 00h OFF), BL = 19h b2:0 burst count (0..7)
        push    bx
        mov     al, 3
        mov     bh, 0F8h
        call    stage_slot
        pop     ax
        mov     bl, ah
        mov     al, 4
        mov     bh, 0FDh
        call    stage_slot
        mov     al, 1
        ret

mf_help:
        mov     byte [want_help], 1
        mov     al, 1
        ret

mf_off:
        ; Reset all tuned bits to safe stock:
        ; 04 b7=0, 05 b1:0=00, 0B b1:0=01, 19 b2:0=00, 18 b4=0 & b1:0=00
        mov     al, 0
        mov     bh, 7Fh
        mov     bl, 00h
        call    stage_slot
        mov     al, 1
        mov     bh, 0FCh
        mov     bl, 00h
        call    stage_slot
        mov     al, 2
        mov     bh, 0FCh
        mov     bl, 01h
        call    stage_slot
        mov     al, 3
        mov     bh, 0F8h
        mov     bl, 00h
        call    stage_slot
        mov     al, 4
        mov     bh, 0ECh
        mov     bl, 00h
        call    stage_slot
        mov     al, 1
        ret

; ---- stage_slot: update pend_tbl[AL] with keep=BH, bits=BL ----
stage_slot:
        mov     di, pend_tbl
        xor     ah, ah
        add     di, ax
        add     di, ax
        add     di, ax              ; DI = pend_tbl + slot*3
        mov     al, [di+1]
        and     al, bh
        mov     [di+1], al
        mov     al, [di+2]
        and     al, bh
        or      al, bl
        mov     [di+2], al
        mov     byte [has_chg], 1
        ret

; ---- acc_read: read ACC2168 reg AL -> AL ----
acc_read:
        cli
        out     0F2h, al
        out     0EDh, al
        in      al, 0F3h
        sti
        ret

; ---- acc_rmw: RMW ACC2168 reg AL = (val & BH) | BL ----
acc_rmw:
        cli
        push    ax
        out     0F2h, al
        out     0EDh, al
        in      al, 0F3h
        and     al, bh
        or      al, bl
        mov     ah, al
        pop     dx                  ; DL = reg index
        mov     al, dl
        out     0F2h, al
        out     0EDh, al
        mov     al, ah
        out     0F3h, al
        out     0EDh, al
        sti
        ret

; ---- print_status: read live 04h/05h/0Bh/18h/19h and display ----
print_status:
        mov     al, 04h
        call    acc_read
        mov     [cur_04], al
        mov     al, 05h
        call    acc_read
        mov     [cur_05], al
        mov     al, 0Bh
        call    acc_read
        mov     [cur_0b], al
        mov     al, 18h
        call    acc_read
        mov     [cur_18], al
        mov     al, 19h
        call    acc_read
        mov     [cur_19], al

        ; Line 1: Regs:  04=XX 05=XX 0B=XX 18=XX 19=XX
        mov     dx, s_r04
        call    print_str
        mov     al, [cur_04]
        call    print_hex

        mov     dx, s_r05
        call    print_str
        mov     al, [cur_05]
        call    print_hex

        mov     dx, s_r0b
        call    print_str
        mov     al, [cur_0b]
        call    print_hex

        mov     dx, s_r18
        call    print_str
        mov     al, [cur_18]
        call    print_hex

        mov     dx, s_r19
        call    print_str
        mov     al, [cur_19]
        call    print_hex

        ; Line 2: State: PW=.. RF=.. BR=.. AT=.. W486=.. CASW=.T PWWS=.. L2=..
        mov     dx, s_pw
        call    print_str
        mov     dx, s_off
        test    byte [cur_04], 80h
        jz      ps_pw
        mov     dx, s_on
ps_pw:
        call    print_str

        mov     dx, s_rf
        call    print_str
        mov     al, [cur_05]
        and     al, 03h
        mov     dx, s_std
        cmp     al, 00h
        je      ps_rf
        mov     dx, s_slow
        cmp     al, 01h
        je      ps_rf
        mov     dx, s_alt
ps_rf:
        call    print_str

        mov     dx, s_br
        call    print_str
        test    byte [cur_18], 02h
        jz      ps_br_off
        mov     al, [cur_19]
        and     al, 07h
        add     al, '1'
        call    print_ch
        jmp     short ps_br_done
ps_br_off:
        mov     dx, s_off
        call    print_str
ps_br_done:

        mov     dx, s_at
        call    print_str
        mov     dx, s_on
        test    byte [cur_18], 01h
        jz      ps_at
        mov     dx, s_off
ps_at:
        call    print_str

        mov     dx, s_w486
        call    print_str
        mov     dx, s_std
        test    byte [cur_04], 40h
        jz      ps_w486
        mov     dx, s_0ws
ps_w486:
        call    print_str

        mov     dx, s_casw
        call    print_str
        mov     al, [cur_0b]
        and     al, 03h
        add     al, '1'
        call    print_ch
        mov     al, 'T'
        call    print_ch

        mov     dx, s_pwws
        call    print_str
        mov     dx, s_1ws
        test    byte [cur_18], 10h
        jz      ps_pwws
        mov     dx, s_0ws
ps_pwws:
        call    print_str

        mov     dx, s_l2
        call    print_str
        mov     dx, s_off
        test    byte [cur_04], 01h
        jz      ps_l2
        mov     dx, s_on
ps_l2:
        call    print_str

        mov     dx, s_crlf
        call    print_str
        ret

; ---- print_str: print $-terminated string at DS:DX ----
print_str:
        mov     ah, 09h
        int     21h
        ret

; ---- print_ch: print single char in AL ----
print_ch:
        mov     dl, al
        mov     ah, 02h
        int     21h
        ret

; ---- print_hex: print AL as 2 uppercase hex digits ----
print_hex:
        push    ax
        mov     cl, 4
        shr     al, cl
        call    print_nib
        pop     ax
        call    print_nib
        ret

print_nib:
        and     al, 0Fh
        add     al, '0'
        cmp     al, '9'
        jbe     pn_out
        add     al, 7
pn_out:
        call    print_ch
        ret

; ---- Data ----
flag_tbl:
        db 1, '?',     0FEh, 0FFh, 00h
        db 1, 'H',     0FEh, 0FFh, 00h
        db 4, 'HELP',  0FEh, 0FFh, 00h
        db 3, 'OFF',   0FFh, 0FFh, 00h
        db 5, 'STOCK', 0FFh, 0FFh, 00h
        db 1, '0',     0FFh, 0FFh, 00h
        db 2, 'PW',    0,    7Fh,  80h
        db 3, 'PW+',   0,    7Fh,  80h
        db 3, 'PW-',   0,    7Fh,  00h
        db 1, 'R',     1,    0FCh, 01h
        db 2, 'R+',    1,    0FCh, 01h
        db 2, 'R-',    1,    0FCh, 00h
        db 2, 'W0',    0,    0BFh, 40h
        db 3, 'W0+',   0,    0BFh, 40h
        db 3, 'W0-',   0,    0BFh, 00h
        db 2, 'C1',    2,    0FCh, 00h
        db 3, 'C1+',   2,    0FCh, 00h
        db 3, 'C1-',   2,    0FCh, 01h
        db 2, 'P0',    4,    0EFh, 10h
        db 3, 'P0+',   4,    0EFh, 10h
        db 3, 'P0-',   4,    0EFh, 00h
        db 2, 'AT',    4,    0FEh, 00h
        db 3, 'AT+',   4,    0FEh, 00h
        db 3, 'AT-',   4,    0FEh, 01h
        db 2, 'BR',    0FDh, 02h,  03h
        db 3, 'BR+',   0FDh, 02h,  03h
        db 3, 'BR-',   0FDh, 00h,  00h
        db 3, 'BR1',   0FDh, 02h,  00h
        db 3, 'BR2',   0FDh, 02h,  01h
        db 3, 'BR3',   0FDh, 02h,  02h
        db 3, 'BR4',   0FDh, 02h,  03h
        db 3, 'BR5',   0FDh, 02h,  04h
        db 3, 'BR6',   0FDh, 02h,  05h
        db 3, 'BR7',   0FDh, 02h,  06h
        db 3, 'BR8',   0FDh, 02h,  07h
        db 0

; Pending RMW slots: (reg_index, and_mask, or_bits) -- 19h written before 18h
pend_tbl:
        db 04h, 0FFh, 00h
        db 05h, 0FFh, 00h
        db 0Bh, 0FFh, 00h
        db 19h, 0FFh, 00h
        db 18h, 0FFh, 00h

has_chg   db 0
want_help db 0
tok_len   db 0
tok_buf   db 0, 0, 0, 0, 0, 0, 0, 0
cur_04    db 0
cur_05    db 0
cur_0b    db 0
cur_18    db 0
cur_19    db 0

msg_hdr   db 'ACCTUNE - ACC 2046/2168 Chipset Tuner', 0Dh, 0Ah, '$'
msg_bad   db 'ACCTUNE: Unknown flag.', 0Dh, 0Ah, '$'
msg_help  db 'Flags (opt-in, combinable; omit + to enable):', 0Dh, 0Ah
          db '  /PW+ /PW-     Posted Write ON/OFF (04h b7)', 0Dh, 0Ah
          db '  /R+  /R-      Slow DRAM Refresh ON/OFF (05h b1:0)', 0Dh, 0Ah
          db '  /BR1..8 /BR-  Burst Refresh ON (1-8, /BR=4) / OFF (18h b1, 19h b2:0)', 0Dh, 0Ah
          db '  /AT- /AT+     AT Bus Refresh OFF/ON (18h b0)', 0Dh, 0Ah
          db '  /W0+ /W0-     486 0-WS Mem Write ON/OFF (04h b6)', 0Dh, 0Ah
          db '  /C1+ /C1-     1T/2T CAS Write (0Bh b1:0; experimental)', 0Dh, 0Ah
          db '  /P0+ /P0-     0-WS/1-WS Posted Write (18h b4; experimental)', 0Dh, 0Ah
          db '  /OFF          Reset all tuned bits to stock (/STOCK, /0)', 0Dh, 0Ah, '$'

s_r04     db 'Regs:  04=$'
s_r05     db ' 05=$'
s_r0b     db ' 0B=$'
s_r18     db ' 18=$'
s_r19     db ' 19=$'
s_pw      db 0Dh, 0Ah, 'State: PW=$'
s_rf      db ' RF=$'
s_br      db ' BR=$'
s_at      db ' AT=$'
s_w486    db ' W486=$'
s_casw    db ' CASW=$'
s_pwws    db ' PWWS=$'
s_l2      db ' L2=$'
s_on      db 'ON$'
s_off     db 'OFF$'
s_std     db 'STD$'
s_slow    db 'SLOW$'
s_alt     db 'ALT$'
s_0ws     db '0WS$'
s_1ws     db '1WS$'
s_crlf    db 0Dh, 0Ah, '$'

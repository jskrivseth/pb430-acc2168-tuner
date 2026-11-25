; POSTWR.COM - ACC Micro 2046/2168 Posted Write & DRAM Refresh utility
;
; Usage:
;   POSTWR       - Posted Write ON (04h b7=1), Refresh Stock (05h b1:0=00)
;   POSTWR /R    - Posted Write ON (04h b7=1), Slow Refresh ON (05h b1:0=01)
;   POSTWR /OFF  - Undo all: Posted Write OFF (04h b7=0), Refresh Stock (05h b1:0=00)
;
; Build with NASM:
;   nasm -f bin postwr.asm -o POSTWR.COM
; Or on Windows without NASM:
;   .\build.ps1

        bits 16
        org 100h

start:
        ; Parse DOS PSP command tail at 0080h (length) / 0081h (text)
        ; BL = mode: 0 = default, 1 = /R, 2 = /OFF (/O, /0)
        mov     si, 0081h
        xor     cx, cx
        mov     cl, [0080h]
        xor     bl, bl
        cld
        jcxz    apply

scan:
        lodsb
        cmp     al, '/'
        je      check_flag
        cmp     al, '-'
        jne     next_ch

check_flag:
        dec     cx
        jz      apply
        lodsb
        cmp     al, '0'
        je      set_off
        or      al, 20h             ; lowercase ASCII
        cmp     al, 'r'
        je      set_r
        cmp     al, 'o'
        jne     next_ch

set_off:
        mov     bl, 2
        jmp     short next_ch

set_r:
        mov     bl, 1

next_ch:
        loop    scan

apply:
        cli

        ; ACC2168 reg 04h: bit 7 = Posted Write Enable
        mov     al, 04h
        out     0F2h, al
        out     0EDh, al            ; I/O delay
        in      al, 0F3h
        cmp     bl, 2
        je      pw_off
        or      al, 80h             ; Posted Write ON
        jmp     short write_04
pw_off:
        and     al, 7Fh             ; Posted Write OFF
write_04:
        mov     ah, al
        mov     al, 04h
        out     0F2h, al
        out     0EDh, al
        mov     al, ah
        out     0F3h, al
        out     0EDh, al

        ; ACC2168 reg 05h: bits 1:0 = DRAM Refresh divisor
        mov     al, 05h
        out     0F2h, al
        out     0EDh, al
        in      al, 0F3h
        and     al, 0FCh            ; reset refresh bits to stock (00)
        cmp     bl, 1
        jne     write_05
        or      al, 01h             ; slow refresh (01)
write_05:
        mov     ah, al
        mov     al, 05h
        out     0F2h, al
        out     0EDh, al
        mov     al, ah
        out     0F3h, al
        out     0EDh, al

        sti

        ; Print active state via DOS INT 21h / AH=09h
        mov     dx, msg_pw
        cmp     bl, 1
        jne     chk_off_msg
        mov     dx, msg_both
        jmp     short print_msg
chk_off_msg:
        cmp     bl, 2
        jne     print_msg
        mov     dx, msg_off

print_msg:
        mov     ah, 09h
        int     21h
        mov     ax, 4C00h
        int     21h

msg_pw   db 'POSTWR: Posted Write ON, Refresh Stock', 0Dh, 0Ah, '$'
msg_both db 'POSTWR: Posted Write ON, Slow Refresh ON', 0Dh, 0Ah, '$'
msg_off  db 'POSTWR: Stock (Posted Write OFF, Refresh Stock)', 0Dh, 0Ah, '$'

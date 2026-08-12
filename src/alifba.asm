; ============================================================
; Alifba v0.1a - fileovyi interpretator literalov (FASM, DOS .COM)
; ============================================================
; Grammar v0.1a (bez peremennykh, bez uslovii, bez perekhodov):
;
;   "stroka" printke      -> vyvesti strokovyi literal
;   chislo printka        -> vyvesti chislovoi literal (desyatichno, so znakom)
;   ; kommentarii         -> ignoriruetsya do kontsa stroki
;
; Primer test01_hello.alf:
;   "Hello, Alifba!" printke
;   255 printka
;   -17 printka   ; otritsatelnoe chislo
;
; Sborka:  fasm alifba_v0_1a_fixed.asm alifba.com
; Zapusk:  alifba.com test01_hello.alf   (v DOSBox)
;
; VAZHNO: pered testom udali staryi alifba.com i peresoberi zanovo,
; chtoby isklyuchit zapusk ustarevshego binarnika.
; ============================================================

        org 100h

; ------------------------------------------------------------
; Konstanty
; ------------------------------------------------------------
LINE_MAX        = 128          ; maks. dlina odnoi stroki iskhodnika
INPUT_MAX       = 8000         ; maks. razmer chitaemogo .alf faila
WORD_MAX        = 32           ; maks. dlina odnogo "slova" (root+suffix)

SUF_UNKNOWN     = 0
SUF_KA          = 1            ; printka
SUF_KE          = 2            ; printke

; ------------------------------------------------------------
; Tochka vkhoda
; ------------------------------------------------------------
start:
        ; --- 1. Razbor komandnoi stroki iz PSP ---
        mov     si, 80h         ; [80h] = dlina khvosta komandnoi stroki
        lodsb
        or      al, al
        jz      .no_args
        mov     cl, al
        xor     ch, ch          ; CX = dlina khvosta

.skip_spaces:
        jcxz    .no_args
        lodsb
        dec     cx
        cmp     al, ' '
        je      .skip_spaces
        dec     si              ; vernutsya na pervyi neprobelnyi simvol
        inc     cx              ; vosstanovit schetchik (simvol eshe ne "ispolzovan")

        ; --- 2. Kopiruem imya faila v filename_buf, ASCIIZ ---
        mov     di, filename_buf
.copy_fn:
        jcxz    .fn_done
        lodsb
        dec     cx
        cmp     al, ' '
        jbe     .fn_done
        cmp     al, 13
        je      .fn_done
        stosb
        jmp     .copy_fn
.fn_done:
        mov     byte [di], 0
        jmp     .have_filename

.no_args:
        mov     dx, msg_usage
        mov     ah, 09h
        int     21h
        jmp     exit_ok

.have_filename:
        ; --- 3. Otkryt fail na chtenie ---
        mov     dx, filename_buf
        mov     ax, 3D00h
        int     21h
        jc      .open_error
        mov     [file_handle], ax

        ; --- 4. Prochitat ves fail v input_buffer ---
        mov     bx, [file_handle]
        mov     cx, INPUT_MAX
        mov     dx, input_buffer
        mov     ah, 3Fh
        int     21h
        jc      .read_error
        mov     [input_len], ax

        ; --- 5. Zakryt fail ---
        mov     bx, [file_handle]
        mov     ah, 3Eh
        int     21h

        ; --- 6. Obrabotat programmu ---
        call    process_program
        jmp     exit_ok

.open_error:
        mov     dx, msg_err_open
        mov     ah, 09h
        int     21h
        jmp     exit_fail

.read_error:
        mov     dx, msg_err_read
        mov     ah, 09h
        int     21h
        jmp     exit_fail

exit_ok:
        mov     ax, 4C00h
        int     21h

exit_fail:
        mov     ax, 4C01h
        int     21h

; ============================================================
; process_program - razbit input_buffer na stroki, obrabotat kazhduyu
; ============================================================
process_program:
        mov     si, input_buffer
        mov     cx, [input_len]

.next_line:
        or      cx, cx
        jz      .prog_done

        mov     di, line_buffer
        xor     dx, dx                  ; DX = dlina tekushei stroki

.read_char:
        or      cx, cx
        jz      .line_end
        lodsb
        dec     cx
        cmp     al, 13                  ; CR
        je      .maybe_lf
        cmp     al, 10                  ; goloi LF
        je      .line_end
        cmp     al, ';'                 ; nachalo kommentariya
        je      .skip_comment
        stosb
        inc     dx
        jmp     .read_char

.skip_comment:
        or      cx, cx
        jz      .line_end
        lodsb
        dec     cx
        cmp     al, 13
        je      .maybe_lf
        cmp     al, 10
        je      .line_end
        jmp     .skip_comment

.maybe_lf:
        or      cx, cx
        jz      .line_end
        mov     al, [si]
        cmp     al, 10
        jne     .line_end
        inc     si
        dec     cx

.line_end:
        mov     byte [di], 0            ; ASCIIZ-terminator stroki
        or      dx, dx
        jz      .next_line              ; pustaya stroka - propustit

        ; --- ISHPRAVLENIE: sohranyaem registry pered obrabotkoi stroki ---
        push    cx                      ; sohranyaem schetchik bajtov faila
        push    si                      ; sohranyaem ukazatel na input_buffer

        call    process_line

        pop     si                      ; vosstanavlivaem ukazatel
        pop     cx                      ; vosstanavlivaem schetchik
        ; -----------------------------------------------------------------

        jmp     .next_line

.prog_done:
        ret

; ============================================================
; process_line - razobrat odnu stroku line_buffer kak vyrazhenie
; Grammar v0.1a:  <operand> <root><suffix>
; ============================================================
process_line:
        mov     si, line_buffer
        call    skip_spaces

        ; --- opredelit tip operanda: stroka ili chislo ---
        mov     al, [si]
        cmp     al, '"'
        je      .parse_string_operand

        ; inache - chislo (vozmozhno so znakom '-')
        call    parse_signed_number     ; -> AX = znachenie, SI za chislom
        mov     [operand_num], ax
        mov     byte [operand_is_str], 0
        jmp     .parse_word

.parse_string_operand:
        inc     si                      ; propustit otkryvayushuyu "
        mov     di, str_literal_buf
.copy_str:
        lodsb
        cmp     al, '"'
        je      .str_done
        cmp     al, 0
        je      .str_done               ; nezakrytaya stroka - prosto obrezhem
        stosb
        jmp     .copy_str
.str_done:
        mov     byte [di], '$'          ; terminator dlya INT 21h/09h
        mov     byte [operand_is_str], 1

.parse_word:
        call    skip_spaces

        ; --- skopirovat root+suffix slovo ---
        mov     di, word_buffer
        xor     cx, cx
.copy_word:
        mov     al, [si]
        cmp     al, ' '
        jbe     .word_done
        stosb
        inc     si
        inc     cx
        cmp     cx, WORD_MAX-1
        jb      .copy_word
.word_done:
        mov     byte [di], 0
        mov     [word_len], cx

        ; --- opredelit suffiks po khvostu slova ---
        call    detect_suffix           ; -> AL = SUF_KA / SUF_KE / SUF_UNKNOWN

        cmp     al, SUF_KA
        je      .do_print_num
        cmp     al, SUF_KE
        je      .do_print_str

        ; neizvestnyi suffiks
        mov     al, 2
        jmp     report_error

.do_print_num:
        cmp     byte [operand_is_str], 1
        je      .type_mismatch          ; printka na stroke - oshibka
        mov     ax, [operand_num]
        call    print_number_signed
        ret

.do_print_str:
        cmp     byte [operand_is_str], 0
        je      .type_mismatch          ; printke na chisle - oshibka (v0.1a)
        mov     dx, str_literal_buf
        mov     ah, 09h
        int     21h
        ret

.type_mismatch:
        mov     al, 1                   ; ERR 1 - sboi singarmonizma
        jmp     report_error

; ============================================================
; detect_suffix - proveryaet khvost word_buffer na "ka" / "ke"
; vkhod: word_buffer (ASCIIZ), word_len
; vykhod: AL = SUF_KA / SUF_KE / SUF_UNKNOWN
; ============================================================
detect_suffix:
        mov     cx, [word_len]
        cmp     cx, 2
        jb      .unknown

        mov     si, word_buffer
        add     si, cx
        sub     si, 2                   ; SI -> poslednie 2 simvola

        mov     al, [si]
        mov     ah, [si+1]

        cmp     al, 'k'
        jne     .unknown
        cmp     ah, 'a'
        je      .is_ka
        cmp     ah, 'e'
        je      .is_ke
        jmp     .unknown

.is_ka:
        mov     al, SUF_KA
        ret
.is_ke:
        mov     al, SUF_KE
        ret
.unknown:
        mov     al, SUF_UNKNOWN
        ret

; ============================================================
; parse_signed_number - chitaet [-]digits iz [SI], prodvigaet SI
; vykhod: AX = znachenie (znakovoe)
; ============================================================
parse_signed_number:
        xor     bx, bx                  ; BX = 0 -> polozhitelnoe, 1 -> otritsatelnoe
        mov     al, [si]
        cmp     al, '-'
        jne     .no_sign
        mov     bx, 1
        inc     si
.no_sign:
        xor     ax, ax                  ; AX = nakoplennoe znachenie
.digit_loop:
        mov     cl, [si]
        cmp     cl, '0'
        jb      .done_digits
        cmp     cl, '9'
        ja      .done_digits
        sub     cl, '0'
        xor     ch, ch
        push    bx
        mov     bx, 10
        mul     bx                      ; AX = AX*10
        pop     bx
        add     ax, cx
        inc     si
        jmp     .digit_loop
.done_digits:
        cmp     bx, 1
        jne     .ret_num
        neg     ax
.ret_num:
        ret

; ============================================================
; print_number_signed - pechataet AX kak desyatichnoe chislo so znakom
; ============================================================
print_number_signed:
        or      ax, ax
        jns     .positive
        push    ax
        mov     dl, '-'
        mov     ah, 02h
        int     21h
        pop     ax
        neg     ax
.positive:
        mov     di, num_buf + 6         ; konets bufera, pishem v obratnom poryadke
        mov     byte [di], '$'
        mov     bx, 10
        mov     cx, 0                   ; schetchik tsifr
.divide_loop:
        xor     dx, dx
        div     bx                      ; AX/10, DX = ostatok
        add     dl, '0'
        dec     di
        mov     [di], dl
        inc     cx
        or      ax, ax
        jnz     .divide_loop
        ; vyvesti poluchivshuyusya stroku
        mov     dx, di
        mov     ah, 09h
        int     21h
        ret

; ============================================================
; skip_spaces - prodvigaet SI vpered, poka [SI] == ' '
; ============================================================
skip_spaces:
.loop:
        mov     al, [si]
        cmp     al, ' '
        jne     .done
        inc     si
        jmp     .loop
.done:
        ret

; ============================================================
; report_error - AL = kod oshibki (1..4), pechataet "ERR N" i vykhodit
; ============================================================
report_error:
        add     al, '0'
        mov     [err_code_char], al
        mov     dx, msg_err
        mov     ah, 09h
        int     21h
        mov     ax, 4C01h
        int     21h

; ------------------------------------------------------------
; Dannye / bufery
; ------------------------------------------------------------
msg_usage       db 'Alifba v0.1a. Usage: alifba.com filename.alf', 13, 10, '$'
msg_err_open    db 'ERR: cannot open file', 13, 10, '$'
msg_err_read    db 'ERR: cannot read file', 13, 10, '$'
msg_err         db 'ERR '
err_code_char   db '0', 13, 10, '$'

file_handle     dw 0
input_len       dw 0

operand_num     dw 0
operand_is_str  db 0
word_len        dw 0

filename_buf    rb 64
line_buffer     rb LINE_MAX
word_buffer     rb WORD_MAX
str_literal_buf rb 256
num_buf         rb 8

input_buffer    rb INPUT_MAX

; ============================================================
; Alifba v0.1c - literaly + peremennye (chislovye i strokovye) + prisvaivanie
; FASM, DOS .COM
; ============================================================
; Grammar v0.1c:
;
;   "stroka" printke      -> vyvesti strokovyi literal
;   chislo printka        -> vyvesti chislovoi literal
;   imya printka / printke -> vyvesti znachenie peremennoi
;   imya = chislo          -> prisvoit chislovoe znachenie (sozdaet, esli net)
;   imya = "stroka"        -> prisvoit strokovoe znachenie (sozdaet, esli net)
;   ; kommentarii          -> ignoriruetsya do kontsa stroki
;
; Sborka:  fasm alifba_v0_1c.asm alifba.com
; Zapusk:  alifba.com test.alf
;
; VAZHNO: pered kazhdym testom udali staryi alifba.com i peresoberi.
; ============================================================

        org 100h

; ------------------------------------------------------------
; Konstanty
; ------------------------------------------------------------
LINE_MAX        = 128
INPUT_MAX       = 8000
WORD_MAX        = 32
MAX_VARS        = 8
NAME_LEN        = 8
STR_HEAP_SIZE   = 2048

SUF_UNKNOWN     = 0
SUF_KA          = 1
SUF_KE          = 2

; ------------------------------------------------------------
; Tochka vkhoda
; ------------------------------------------------------------
start:
        mov     si, 80h
        lodsb
        or      al, al
        jz      .no_args
        mov     cl, al
        xor     ch, ch

.skip_spaces:
        jcxz    .no_args
        lodsb
        dec     cx
        cmp     al, ' '
        je      .skip_spaces
        dec     si
        inc     cx

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
        mov     dx, filename_buf
        mov     ax, 3D00h
        int     21h
        jc      .open_error
        mov     [file_handle], ax

        mov     bx, [file_handle]
        mov     cx, INPUT_MAX
        mov     dx, input_buffer
        mov     ah, 3Fh
        int     21h
        jc      .read_error
        mov     [input_len], ax

        mov     bx, [file_handle]
        mov     ah, 3Eh
        int     21h

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
; process_program
; ============================================================
process_program:
        mov     si, input_buffer
        mov     cx, [input_len]

.next_line:
        or      cx, cx
        jz      .prog_done

        mov     di, line_buffer
        xor     dx, dx

.read_char:
        or      cx, cx
        jz      .line_end
        lodsb
        dec     cx
        cmp     al, 13
        je      .maybe_lf
        cmp     al, 10
        je      .line_end
        cmp     al, ';'
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
        mov     byte [di], 0
        or      dx, dx
        jz      .next_line

        ; --- KRITICHNO: sokhranyaem registry vneshnego tsikla ---
        push    cx
        push    si
        call    process_line
        pop     si
        pop     cx
        ; ---------------------------------------------------------

        jmp     .next_line

.prog_done:
        ret

; ============================================================
; process_line
; ============================================================
process_line:
        mov     si, line_buffer
        call    skip_spaces

        mov     al, [si]
        cmp     al, '"'
        je      .parse_string_operand
        cmp     al, '-'
        je      .parse_number_operand
        cmp     al, '0'
        jb      .parse_identifier
        cmp     al, '9'
        jbe     .parse_number_operand
        jmp     .parse_identifier

; ---------- chislovoi literal kak operand pechati ----------
.parse_number_operand:
        call    parse_signed_number
        mov     [operand_num], ax
        mov     byte [operand_is_str], 0
        jmp     .parse_word

; ---------- strokovyi literal kak operand pechati ----------
.parse_string_operand:
        inc     si
        mov     di, str_literal_buf
.copy_str:
        lodsb
        cmp     al, '"'
        je      .str_done
        cmp     al, 0
        je      .str_done
        stosb
        jmp     .copy_str
.str_done:
        mov     byte [di], '$'
        mov     word [operand_str_ptr], str_literal_buf
        mov     byte [operand_is_str], 1
        jmp     .parse_word

; ---------- identifikator: mozhet byt prisvaivaniem ili chteniem ----------
.parse_identifier:
        mov     di, var_name_buf
.copy_ident:
        mov     al, [si]
        cmp     al, ' '
        jbe     .ident_done
        cmp     al, '='
        je      .ident_done
        stosb
        inc     si
        jmp     .copy_ident
.ident_done:
        mov     byte [di], 0

        push    si                       ; sokhranyaem poziciyu srazu posle identifikatora
        call    skip_spaces
        mov     al, [si]
        cmp     al, '='
        je      .do_assignment
        pop     si                       ; ne prisvaivanie - vosstanavlivaem poziciyu
        jmp     .var_read

; ---------- prisvaivanie: imya = znachenie ----------
.do_assignment:
        pop     dx                       ; otbrasyvaem sokhranenniy si (ne nuzhen na etom puti)
        inc     si                       ; propuskaem '='
        call    skip_spaces
        mov     al, [si]
        cmp     al, '"'
        je      .assign_string

        ; prisvaivanie chisla
        call    parse_signed_number      ; -> ax = znachenie
        push    ax
        mov     si, var_name_buf
        call    find_or_create_var_num   ; -> bx = indeks
        pop     ax
        call    set_var_num
        ret

.assign_string:
        inc     si
        mov     di, str_literal_buf
.copy_assign_str:
        lodsb
        cmp     al, '"'
        je      .assign_str_done
        cmp     al, 0
        je      .assign_str_done
        stosb
        jmp     .copy_assign_str
.assign_str_done:
        mov     byte [di], '$'
        mov     si, var_name_buf
        call    find_or_create_var_str   ; -> bx = indeks
        call    store_var_string         ; bx=indeks, kopiruet str_literal_buf v kuchu
        ret

; ---------- chtenie peremennoi (dlya posleduyushei pechati) ----------
.var_read:
        push    si
        mov     si, var_name_buf
        call    find_var                 ; -> bx=indeks, al=tip (0/1); esli net - vyhod s ERR5
        pop     si
        cmp     al, 1
        je      .var_read_string
        call    get_var_num
        mov     [operand_num], ax
        mov     byte [operand_is_str], 0
        jmp     .parse_word
.var_read_string:
        call    get_var_str_ptr          ; bx -> dx = pointer
        mov     [operand_str_ptr], dx
        mov     byte [operand_is_str], 1
        jmp     .parse_word

; ---------- razbor slova root+suffix i vyvod ----------
.parse_word:
        call    skip_spaces
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

        call    detect_suffix
        cmp     al, SUF_KA
        je      .do_print_num
        cmp     al, SUF_KE
        je      .do_print_str
        mov     al, 2
        jmp     report_error

.do_print_num:
        cmp     byte [operand_is_str], 1
        je      .type_mismatch
        mov     ax, [operand_num]
        call    print_number_signed
        call    print_crlf
        ret

.do_print_str:
        cmp     byte [operand_is_str], 0
        je      .type_mismatch
        mov     dx, [operand_str_ptr]
        mov     ah, 09h
        int     21h
        call    print_crlf
        ret

.type_mismatch:
        mov     al, 1
        jmp     report_error

; ============================================================
; find_var - poisk peremennoi po imeni (BEZ sozdaniya)
; vkhod: si -> ASCIIZ imya
; vykhod: bx = indeks, al = tip (0/1)
; esli ne naidena - report_error(5), programma zavershaetsya
; ============================================================
find_var:
        push    cx
        push    dx
        push    di
        mov     cx, [var_count]
        xor     bx, bx
        or      cx, cx
        jz      .not_found
.search_loop:
        cmp     bx, cx
        jae     .not_found
        mov     ax, bx
        mov     dx, NAME_LEN+1
        mul     dx
        mov     di, var_names
        add     di, ax
        call    strcmp_asciiz
        cmp     al, 1
        je      .found
        inc     bx
        jmp     .search_loop
.found:
        mov     ax, bx
        mov     di, var_types
        add     di, ax
        mov     al, [di]
        pop     di
        pop     dx
        pop     cx
        ret
.not_found:
        mov     al, 5
        jmp     report_error

; ============================================================
; find_or_create_var_num - poisk ili sozdanie CHISLOVOI peremennoi
; vkhod: si -> ASCIIZ imya
; vykhod: bx = indeks
; esli naidena s drugim tipom - ERR 7; esli tablitsa polna - ERR 8
; ============================================================
find_or_create_var_num:
        push    ax
        push    cx
        push    dx
        push    di
        mov     cx, [var_count]
        xor     bx, bx
        or      cx, cx
        jz      .create
.search:
        cmp     bx, cx
        jae     .create
        mov     ax, bx
        mov     dx, NAME_LEN+1
        mul     dx
        mov     di, var_names
        add     di, ax
        call    strcmp_asciiz
        cmp     al, 1
        je      .check_type
        inc     bx
        jmp     .search
.check_type:
        mov     ax, bx
        mov     di, var_types
        add     di, ax
        cmp     byte [di], 0
        jne     .type_conflict
        jmp     .done
.create:
        mov     bx, [var_count]
        cmp     bx, MAX_VARS
        jae     .table_full
        mov     ax, bx
        mov     dx, NAME_LEN+1
        mul     dx
        mov     di, var_names
        add     di, ax
.copy_name:
        lodsb
        stosb
        or      al, al
        jnz     .copy_name
        mov     ax, bx
        mov     di, var_types
        add     di, ax
        mov     byte [di], 0
        mov     ax, bx
        shl     ax, 1
        mov     di, var_values
        add     di, ax
        mov     word [di], 0
        inc     word [var_count]
.done:
        pop     di
        pop     dx
        pop     cx
        pop     ax
        ret
.type_conflict:
        mov     al, 7
        jmp     report_error
.table_full:
        mov     al, 8
        jmp     report_error

; ============================================================
; find_or_create_var_str - poisk ili sozdanie STROKOVOI peremennoi
; (analogichno find_or_create_var_num, no tip = 1)
; ============================================================
find_or_create_var_str:
        push    ax
        push    cx
        push    dx
        push    di
        mov     cx, [var_count]
        xor     bx, bx
        or      cx, cx
        jz      .create
.search:
        cmp     bx, cx
        jae     .create
        mov     ax, bx
        mov     dx, NAME_LEN+1
        mul     dx
        mov     di, var_names
        add     di, ax
        call    strcmp_asciiz
        cmp     al, 1
        je      .check_type
        inc     bx
        jmp     .search
.check_type:
        mov     ax, bx
        mov     di, var_types
        add     di, ax
        cmp     byte [di], 1
        jne     .type_conflict
        jmp     .done
.create:
        mov     bx, [var_count]
        cmp     bx, MAX_VARS
        jae     .table_full
        mov     ax, bx
        mov     dx, NAME_LEN+1
        mul     dx
        mov     di, var_names
        add     di, ax
.copy_name:
        lodsb
        stosb
        or      al, al
        jnz     .copy_name
        mov     ax, bx
        mov     di, var_types
        add     di, ax
        mov     byte [di], 1
        mov     ax, bx
        shl     ax, 1
        mov     di, var_values
        add     di, ax
        mov     word [di], 0
        inc     word [var_count]
.done:
        pop     di
        pop     dx
        pop     cx
        pop     ax
        ret
.type_conflict:
        mov     al, 7
        jmp     report_error
.table_full:
        mov     al, 8
        jmp     report_error

; ============================================================
; strcmp_asciiz - sravnenie dvukh ASCIIZ-strok
; vkhod: si -> stroka 1, di -> stroka 2
; vykhod: al = 1 esli ravny, al = 0 esli net (si, di vosstanavlivayutsya)
; ============================================================
strcmp_asciiz:
        push    si
        push    di
.loop:
        mov     al, [si]
        mov     ah, [di]
        cmp     al, ah
        jne     .not_equal
        or      al, al
        jz      .is_equal
        inc     si
        inc     di
        jmp     .loop
.is_equal:
        pop     di
        pop     si
        mov     al, 1
        ret
.not_equal:
        pop     di
        pop     si
        xor     al, al
        ret

; ============================================================
; get_var_num - vkhod: bx=indeks; vykhod: ax=znachenie
; ============================================================
get_var_num:
        push    di
        mov     ax, bx
        shl     ax, 1
        mov     di, var_values
        add     di, ax
        mov     ax, [di]
        pop     di
        ret

; ============================================================
; set_var_num - vkhod: bx=indeks, ax=znachenie dlya zapisi
; ============================================================
set_var_num:
        push    di
        push    ax
        mov     ax, bx
        shl     ax, 1
        mov     di, var_values
        add     di, ax
        pop     ax
        mov     [di], ax
        pop     di
        ret

; ============================================================
; get_var_str_ptr - vkhod: bx=indeks; vykhod: dx=pointer na stroku v kuche
; ============================================================
get_var_str_ptr:
        push    di
        mov     ax, bx
        shl     ax, 1
        mov     di, var_values
        add     di, ax
        mov     dx, [di]
        pop     di
        ret

; ============================================================
; store_var_string - kopiruet str_literal_buf ('$'-terminated) v kuchu
; i sokhranyaet ukazatel v var_values[bx]
; vkhod: bx = indeks peremennoi
; ============================================================
store_var_string:
        push    ax
        push    si
        push    di
        mov     di, [str_heap_ptr]
        mov     ax, di                   ; ax = nachalnyi adres novoi stroki
        push    ax
        mov     si, str_literal_buf
.copy_loop:
        lodsb
        stosb
        cmp     al, '$'
        jne     .copy_loop
        mov     [str_heap_ptr], di       ; sdvigaem ukazatel kuchi za terminator
        pop     ax                       ; ax = pointer, kotoryi sohranyaem
        mov     di, bx
        shl     di, 1
        add     di, var_values
        mov     [di], ax
        pop     di
        pop     si
        pop     ax
        ret

; ============================================================
; detect_suffix
; ============================================================
detect_suffix:
        mov     cx, [word_len]
        cmp     cx, 2
        jb      .unknown
        mov     si, word_buffer
        add     si, cx
        sub     si, 2
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
; parse_signed_number
; ============================================================
parse_signed_number:
        xor     bx, bx
        mov     al, [si]
        cmp     al, '-'
        jne     .no_sign
        mov     bx, 1
        inc     si
.no_sign:
        xor     ax, ax
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
        mul     bx
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
; print_number_signed
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
        mov     di, num_buf + 6
        mov     byte [di], '$'
        mov     bx, 10
        mov     cx, 0
.divide_loop:
        xor     dx, dx
        div     bx
        add     dl, '0'
        dec     di
        mov     [di], dl
        inc     cx
        or      ax, ax
        jnz     .divide_loop
        mov     dx, di
        mov     ah, 09h
        int     21h
        ret

; ============================================================
; print_crlf
; ============================================================
print_crlf:
        push    ax
        push    dx
        mov     dl, 13
        mov     ah, 02h
        int     21h
        mov     dl, 10
        int     21h
        pop     dx
        pop     ax
        ret

; ============================================================
; skip_spaces
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
; report_error
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
msg_usage       db 'Alifba v0.1c. Usage: alifba.com filename.alf', 13, 10, '$'
msg_err_open    db 'ERR: cannot open file', 13, 10, '$'
msg_err_read    db 'ERR: cannot read file', 13, 10, '$'
msg_err         db 'ERR '
err_code_char   db '0', 13, 10, '$'

file_handle     dw 0
input_len       dw 0

operand_num     dw 0
operand_is_str  db 0
operand_str_ptr dw 0
word_len        dw 0

; --- Tablitsa peremennykh (nachinaet pustoi, zapolnyaetsya cherez '=') ---
var_names:
        times   MAX_VARS*(NAME_LEN+1) db 0
var_types:
        times   MAX_VARS db 0
var_values:
        times   MAX_VARS dw 0
var_count       dw 0

; --- Kucha dlya strokovykh peremennykh ---
str_heap        rb STR_HEAP_SIZE
str_heap_ptr    dw str_heap

filename_buf    rb 64
line_buffer     rb LINE_MAX
word_buffer     rb WORD_MAX
var_name_buf    rb NAME_LEN+1
str_literal_buf rb 256
num_buf         rb 8

input_buffer    rb INPUT_MAX

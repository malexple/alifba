; ============================================================
; Alifba v0.1g - dobavlena konkatenatsiya strok cherez -is/-es
; (simmetrichno chislovomu slozheniyu iz v0.1f)
; FASM, DOS .COM
; ============================================================
; Novaya grammatika:
;
;   imya = strokaA strokaBis   -> konkatenatsiya (strokaA + strokaB)
;   imya = "tekst"              -> prostoe prisvaivanie (kak ranshe)
;   imya = drugaya_peremennaya  -> kopirovanie (chislo ili stroka - po tipu istochnika)
;
; Primer:
;   greeting = "Hello, "
;   name = "Alifba"
;   message = greeting name is
;   message printke        -> "Hello, Alifba"
;
; Sborka:  fasm alifba_v0_1g.asm alifba.com
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
MAX_LABELS      = 8
LABEL_NAME_LEN  = 8
CONCAT_BUF_SIZE = 512

SUF_UNKNOWN     = 0
SUF_KA          = 1
SUF_KE          = 2

CSUF_UNKNOWN    = 0
CSUF_EQ_GOTO    = 1
CSUF_NEQ_GOTO   = 2

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
        mov     ax, input_buffer
        add     ax, [input_len]
        mov     [input_end], ax

        call    scan_labels

        mov     si, input_buffer

.next_line:
        cmp     si, [input_end]
        jae     .prog_done

        mov     di, line_buffer
        xor     dx, dx

.read_char:
        cmp     si, [input_end]
        jae     .line_end
        lodsb
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
        cmp     si, [input_end]
        jae     .line_end
        lodsb
        cmp     al, 13
        je      .maybe_lf
        cmp     al, 10
        je      .line_end
        jmp     .skip_comment

.maybe_lf:
        cmp     si, [input_end]
        jae     .line_end
        mov     al, [si]
        cmp     al, 10
        jne     .line_end
        inc     si

.line_end:
        mov     byte [di], 0
        or      dx, dx
        jz      .next_line

        push    si
        call    process_line
        pop     si

        cmp     byte [jump_requested], 1
        jne     .next_line
        mov     byte [jump_requested], 0
        mov     si, [jump_target]
        jmp     .next_line

.prog_done:
        ret

; ============================================================
; scan_labels
; ============================================================
scan_labels:
        push    si
        push    di
        push    ax
        push    bx
        push    cx
        push    dx

        mov     si, input_buffer

.scan_loop:
        cmp     si, [input_end]
        jae     .scan_done

        mov     di, scan_line_buffer
        mov     word [scan_line_len], 0

.scan_char:
        cmp     si, [input_end]
        jae     .scan_eol
        lodsb
        cmp     al, 13
        je      .scan_crlf
        cmp     al, 10
        je      .scan_eol
        cmp     al, ';'
        je      .scan_comment
        stosb
        inc     word [scan_line_len]
        jmp     .scan_char

.scan_comment:
        cmp     si, [input_end]
        jae     .scan_eol
        lodsb
        cmp     al, 13
        je      .scan_crlf
        cmp     al, 10
        je      .scan_eol
        jmp     .scan_comment

.scan_crlf:
        cmp     si, [input_end]
        jae     .scan_eol
        mov     al, [si]
        cmp     al, 10
        jne     .scan_eol
        inc     si

.scan_eol:
        mov     byte [di], 0
        cmp     word [scan_line_len], 0
        je      .scan_loop

        mov     bx, scan_line_buffer
        add     bx, [scan_line_len]
        dec     bx
        cmp     byte [bx], ':'
        jne     .scan_loop

        mov     byte [bx], 0

        mov     bx, [label_count]
        cmp     bx, MAX_LABELS
        jae     .scan_loop

        mov     ax, bx
        mov     cx, LABEL_NAME_LEN+1
        mul     cx
        mov     di, label_names
        add     di, ax

        mov     dx, si
        mov     si, scan_line_buffer
.copy_label_name:
        lodsb
        stosb
        or      al, al
        jnz     .copy_label_name
        mov     si, dx

        mov     ax, bx
        shl     ax, 1
        mov     di, label_positions
        add     di, ax
        mov     [di], si

        inc     word [label_count]
        jmp     .scan_loop

.scan_done:
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        pop     di
        pop     si
        ret

; ============================================================
; find_label
; ============================================================
find_label:
        push    ax
        push    bx
        push    cx
        push    di
        mov     cx, [label_count]
        xor     bx, bx
        or      cx, cx
        jz      .not_found
.search:
        cmp     bx, cx
        jae     .not_found
        push    cx
        mov     ax, bx
        mov     cx, LABEL_NAME_LEN+1
        mul     cx
        pop     cx
        mov     di, label_names
        add     di, ax
        call    strcmp_asciiz
        cmp     al, 1
        je      .found
        inc     bx
        jmp     .search
.found:
        mov     ax, bx
        shl     ax, 1
        mov     di, label_positions
        add     di, ax
        mov     dx, [di]
        pop     di
        pop     cx
        pop     bx
        pop     ax
        ret
.not_found:
        mov     al, 9
        jmp     report_error

; ============================================================
; classify_condition_suffix
; ============================================================
classify_condition_suffix:
        push    di
        mov     di, str_saga
        call    strcmp_asciiz
        cmp     al, 1
        je      .eq
        mov     di, str_sege
        call    strcmp_asciiz
        cmp     al, 1
        je      .eq
        mov     di, str_masaga
        call    strcmp_asciiz
        cmp     al, 1
        je      .neq
        mov     di, str_mesege
        call    strcmp_asciiz
        cmp     al, 1
        je      .neq
        pop     di
        mov     al, CSUF_UNKNOWN
        ret
.eq:
        pop     di
        mov     al, CSUF_EQ_GOTO
        ret
.neq:
        pop     di
        mov     al, CSUF_NEQ_GOTO
        ret

; ============================================================
; check_is_es_suffix - proveryaet, chto word_buffer/[word_len] eto
; tochno "is" ili "es". Esli net - report_error(2) (ne vozvrashaetsya)
; ============================================================
check_is_es_suffix:
        cmp     word [word_len], 2
        jne     .bad
        mov     al, [word_buffer]
        cmp     al, 'i'
        je      .check_i2
        cmp     al, 'e'
        je      .check_e2
        jmp     .bad
.check_i2:
        cmp     byte [word_buffer+1], 's'
        jne     .bad
        ret
.check_e2:
        cmp     byte [word_buffer+1], 's'
        jne     .bad
        ret
.bad:
        mov     al, 2
        jmp     report_error

; ============================================================
; parse_value - universalnyi razbor odnogo znacheniya
; ============================================================
parse_value:
        mov     al, [si]
        cmp     al, '"'
        je      .val_string
        cmp     al, '-'
        je      .val_number
        cmp     al, '0'
        jb      .val_identifier
        cmp     al, '9'
        jbe     .val_number
        jmp     .val_identifier

.val_number:
        call    parse_signed_number
        mov     [value_num], ax
        mov     byte [value_is_str], 0
        ret

.val_string:
        inc     si
        mov     di, value_str_buf
.copy_vstr:
        lodsb
        cmp     al, '"'
        je      .vstr_done
        cmp     al, 0
        je      .vstr_done
        stosb
        jmp     .copy_vstr
.vstr_done:
        mov     byte [di], '$'
        mov     word [value_str_ptr], value_str_buf
        mov     byte [value_is_str], 1
        ret

.val_identifier:
        mov     di, value_ident_buf
.copy_vident:
        mov     al, [si]
        cmp     al, ' '
        jbe     .vident_done
        stosb
        inc     si
        jmp     .copy_vident
.vident_done:
        mov     byte [di], 0
        push    si
        mov     si, value_ident_buf
        call    find_var
        pop     si
        cmp     al, 1
        je      .vident_is_str
        call    get_var_num
        mov     [value_num], ax
        mov     byte [value_is_str], 0
        ret
.vident_is_str:
        call    get_var_str_ptr
        mov     [value_str_ptr], dx
        mov     byte [value_is_str], 1
        ret

; ============================================================
; copy_value_str_to_concat_buf / append_value_str_to_concat_buf
; kopiruyut iz [value_str_ptr] ('$'-terminated) v concat_buf
; ============================================================
copy_value_str_to_concat_buf:
        push    ax
        push    si
        push    di
        mov     si, [value_str_ptr]
        mov     di, concat_buf
        mov     word [concat_len], 0
.loop:
        lodsb
        cmp     al, '$'
        je      .done
        stosb
        inc     word [concat_len]
        jmp     .loop
.done:
        pop     di
        pop     si
        pop     ax
        ret

append_value_str_to_concat_buf:
        push    ax
        push    si
        push    di
        mov     si, [value_str_ptr]
        mov     di, concat_buf
        add     di, [concat_len]
.loop:
        lodsb
        cmp     al, '$'
        je      .done
        stosb
        inc     word [concat_len]
        jmp     .loop
.done:
        pop     di
        pop     si
        pop     ax
        ret

; ============================================================
; store_var_string_from_concat_buf - sohranyaet soderzhimoe concat_buf
; v peremennuyu, na kotoruyu ukazyvaet BX (indeks, uzhe naiden/sozdan)
; ============================================================
store_var_string_from_concat_buf:
        push    ax
        push    cx
        push    si
        push    di
        mov     si, concat_buf
        mov     di, str_literal_buf
        mov     cx, [concat_len]
.copy_loop:
        jcxz    .copy_done
        lodsb
        stosb
        dec     cx
        jmp     .copy_loop
.copy_done:
        mov     byte [di], '$'
        pop     di
        pop     si
        pop     cx
        pop     ax
        call    store_var_string
        ret

; ============================================================
; process_line
; ============================================================
process_line:
        mov     si, line_buffer
        call    skip_spaces

        push    si
        mov     di, si
.find_line_end:
        mov     al, [di]
        or      al, al
        jz      .checked_line_end
        inc     di
        jmp     .find_line_end
.checked_line_end:
        cmp     di, si
        je      .not_a_label_def
        dec     di
        cmp     byte [di], ':'
        jne     .not_a_label_def
        pop     ax
        ret
.not_a_label_def:
        pop     si

        push    si
        mov     di, goto_check_buf
        xor     cx, cx
.goto_scan:
        mov     al, [si]
        cmp     al, ' '
        jbe     .goto_scan_done
        stosb
        inc     si
        inc     cx
        cmp     cx, WORD_MAX-1
        jb      .goto_scan
.goto_scan_done:
        mov     byte [di], 0

        push    si
        call    skip_spaces
        mov     al, [si]
        pop     si
        or      al, al
        jnz     .not_a_goto

        cmp     cx, 3
        jb      .not_a_goto
        mov     bx, goto_check_buf
        add     bx, cx
        sub     bx, 2
        mov     al, [bx]
        cmp     al, 'g'
        jne     .not_a_goto
        mov     al, [bx+1]
        cmp     al, 'a'
        je      .is_goto
        cmp     al, 'e'
        je      .is_goto
        jmp     .not_a_goto

.is_goto:
        pop     ax
        mov     byte [bx], 0
        mov     si, goto_check_buf
        call    find_label
        mov     [jump_target], dx
        mov     byte [jump_requested], 1
        ret

.not_a_goto:
        pop     si

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

.parse_number_operand:
        call    parse_signed_number
        mov     [operand_num], ax
        mov     byte [operand_is_str], 0
        jmp     .parse_word

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

        push    si
        call    skip_spaces
        mov     al, [si]
        cmp     al, '='
        je      .do_assignment
        pop     si
        jmp     .var_read

; ---------- prisvaivanie: chisla ili stroki, s opciyonalnym is/es ----------
.do_assignment:
        pop     dx
        inc     si
        call    skip_spaces

        call    parse_value

        cmp     byte [value_is_str], 1
        je      .rhs_is_string

        ; ---- CHISLOVAYA vetv ----
        mov     ax, [value_num]
        mov     [rhs_a], ax

        push    si
        call    skip_spaces
        mov     al, [si]
        pop     si
        or      al, al
        jz      .simple_num_assign

        call    skip_spaces
        call    parse_value
        cmp     byte [value_is_str], 1
        je      .arith_error
        mov     ax, [value_num]
        mov     [rhs_b], ax

        call    skip_spaces
        mov     di, word_buffer
        xor     cx, cx
.copy_num_suffix:
        mov     al, [si]
        cmp     al, ' '
        jbe     .num_suffix_done
        stosb
        inc     si
        inc     cx
        cmp     cx, WORD_MAX-1
        jb      .copy_num_suffix
.num_suffix_done:
        mov     byte [di], 0
        mov     [word_len], cx
        call    check_is_es_suffix

        mov     ax, [rhs_a]
        add     ax, [rhs_b]
        mov     [rhs_a], ax
        push    si
        mov     si, var_name_buf
        call    find_or_create_var_num
        pop     si
        mov     ax, [rhs_a]
        call    set_var_num
        ret

.simple_num_assign:
        push    si
        mov     si, var_name_buf
        call    find_or_create_var_num
        pop     si
        mov     ax, [rhs_a]
        call    set_var_num
        ret

.arith_error:
        mov     al, 1
        jmp     report_error

; ---- STROKOVAYA vetv ----
.rhs_is_string:
        call    copy_value_str_to_concat_buf

        push    si
        call    skip_spaces
        mov     al, [si]
        pop     si
        or      al, al
        jz      .simple_str_assign

        call    skip_spaces
        call    parse_value
        cmp     byte [value_is_str], 0
        je      .arith_error

        call    append_value_str_to_concat_buf

        call    skip_spaces
        mov     di, word_buffer
        xor     cx, cx
.copy_str_suffix:
        mov     al, [si]
        cmp     al, ' '
        jbe     .str_suffix_done
        stosb
        inc     si
        inc     cx
        cmp     cx, WORD_MAX-1
        jb      .copy_str_suffix
.str_suffix_done:
        mov     byte [di], 0
        mov     [word_len], cx
        call    check_is_es_suffix

        mov     si, var_name_buf
        call    find_or_create_var_str
        call    store_var_string_from_concat_buf
        ret

.simple_str_assign:
        mov     si, var_name_buf
        call    find_or_create_var_str
        call    store_var_string_from_concat_buf
        ret

.var_read:
        push    si
        mov     si, var_name_buf
        call    find_var
        pop     si
        cmp     al, 1
        je      .var_read_string
        call    get_var_num
        mov     [operand_num], ax
        mov     byte [operand_is_str], 0
        jmp     .parse_word
.var_read_string:
        call    get_var_str_ptr
        mov     [operand_str_ptr], dx
        mov     byte [operand_is_str], 1
        jmp     .parse_word

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

        mov     al, [word_buffer]
        cmp     al, '-'
        je      .is_condition_word
        cmp     al, '0'
        jb      .is_print_word
        cmp     al, '9'
        jbe     .is_condition_word
        jmp     .is_print_word

.is_print_word:
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

.is_condition_word:
        push    si
        mov     si, word_buffer
        call    parse_signed_number
        mov     [compare_value], ax
        call    classify_condition_suffix
        mov     [condition_kind], al
        pop     si

        cmp     byte [condition_kind], 0
        je      .unknown_condition_suffix

        call    skip_spaces
        mov     di, goto_check_buf
        xor     cx, cx
.copy_target:
        mov     al, [si]
        cmp     al, ' '
        jbe     .target_done
        stosb
        inc     si
        inc     cx
        cmp     cx, WORD_MAX-1
        jb      .copy_target
.target_done:
        mov     byte [di], 0
        cmp     cx, 0
        je      .missing_target

        cmp     byte [operand_is_str], 1
        je      .cond_type_mismatch

        mov     ax, [operand_num]
        cmp     ax, [compare_value]
        je      .values_equal

        cmp     byte [condition_kind], CSUF_NEQ_GOTO
        je      .do_condition_jump
        ret

.values_equal:
        cmp     byte [condition_kind], CSUF_EQ_GOTO
        je      .do_condition_jump
        ret

.do_condition_jump:
        mov     si, goto_check_buf
        call    find_label
        mov     [jump_target], dx
        mov     byte [jump_requested], 1
        ret

.unknown_condition_suffix:
        mov     al, 2
        jmp     report_error

.missing_target:
        mov     al, 10
        jmp     report_error

.cond_type_mismatch:
        mov     al, 1
        jmp     report_error

; ============================================================
; find_var
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
; find_or_create_var_num
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
; find_or_create_var_str
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
; strcmp_asciiz
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
; get_var_num / set_var_num / get_var_str_ptr / store_var_string
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

get_var_str_ptr:
        push    di
        mov     ax, bx
        shl     ax, 1
        mov     di, var_values
        add     di, ax
        mov     dx, [di]
        pop     di
        ret

store_var_string:
        push    ax
        push    si
        push    di
        mov     di, [str_heap_ptr]
        mov     ax, di
        push    ax
        mov     si, str_literal_buf
.copy_loop:
        lodsb
        stosb
        cmp     al, '$'
        jne     .copy_loop
        mov     [str_heap_ptr], di
        pop     ax
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
msg_usage       db 'Alifba v0.1g. Usage: alifba.com filename.alf', 13, 10, '$'
msg_err_open    db 'ERR: cannot open file', 13, 10, '$'
msg_err_read    db 'ERR: cannot read file', 13, 10, '$'
msg_err         db 'ERR '
err_code_char   db '0', 13, 10, '$'

str_saga        db 'saga',0
str_sege        db 'sege',0
str_masaga      db 'masaga',0
str_mesege      db 'mesege',0

file_handle     dw 0
input_len       dw 0
input_end       dw 0

operand_num     dw 0
operand_is_str  db 0
operand_str_ptr dw 0
word_len        dw 0

jump_requested  db 0
jump_target     dw 0

compare_value   dw 0
condition_kind  db 0

value_is_str    db 0
value_num       dw 0
value_str_ptr   dw 0
value_str_buf   rb 256
value_ident_buf rb NAME_LEN+1

rhs_a           dw 0
rhs_b           dw 0

concat_buf      rb CONCAT_BUF_SIZE
concat_len      dw 0

; --- Tablitsa peremennykh ---
var_names:
        times   MAX_VARS*(NAME_LEN+1) db 0
var_types:
        times   MAX_VARS db 0
var_values:
        times   MAX_VARS dw 0
var_count       dw 0

; --- Tablitsa metok ---
label_names:
        times   MAX_LABELS*(LABEL_NAME_LEN+1) db 0
label_positions:
        times   MAX_LABELS dw 0
label_count     dw 0

; --- Kucha dlya strokovykh peremennykh ---
str_heap        rb STR_HEAP_SIZE
str_heap_ptr    dw str_heap

filename_buf    rb 64
line_buffer     rb LINE_MAX
word_buffer     rb WORD_MAX
var_name_buf    rb NAME_LEN+1
goto_check_buf  rb WORD_MAX
scan_line_buffer rb LINE_MAX
scan_line_len   dw 0
str_literal_buf rb 256
num_buf         rb 8

input_buffer    rb INPUT_MAX

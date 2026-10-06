bits 16
%include "src/layout.inc"
org 0x100

BOARD_ROW   equ WIN_CONTENT_ROW + 2
BOARD_COL   equ WIN_CONTENT_COL + 12
TITLE_ROW   equ WIN_CONTENT_ROW
STATUS_ROW  equ WIN_CONTENT_ROW + 12
HINT_ROW    equ WIN_CONTENT_ROW + 13

start:
    mov ax, 0xb800
    mov es, ax

    call build_piece_list
    call draw_all

game_loop:
    xor ah, ah
    int 0x16

    cmp al, 3 ; Ctrl+C
    je .quit
    cmp al, `\r` ; Enter
    je .on_enter

    cmp byte [phase], 0
    je .select_keys

    mov bx, [cur_row]
    mov cx, [cur_col]
    cmp ah, 0x48 ; up
    jne .mv_chk_down
    dec bx
    jmp .mv_try
.mv_chk_down:
    cmp ah, 0x50 ; down
    jne .mv_chk_left
    inc bx
    jmp .mv_try
.mv_chk_left:
    cmp ah, 0x4b ; left
    jne .mv_chk_right
    dec cx
    jmp .mv_try
.mv_chk_right:
    cmp ah, 0x4d ; right
    jne .after_key
    inc cx
.mv_try:
    cmp bx, 8
    ja .after_key
    cmp cx, 8
    ja .after_key
    call is_legal_cursor_move
    test al, al
    je .after_key
    mov [cur_row], bx
    mov [cur_col], cx
    jmp .after_key

.select_keys:
    mov bx, [piece_index]
    cmp ah, 0x4b ; left
    jne .sk_chk_right
    test bx, bx
    jne .sk_dec
    mov bx, [piece_count]
.sk_dec:
    dec bx
    jmp .sk_have
.sk_chk_right:
    cmp ah, 0x4d ; right
    jne .after_key
    inc bx
    cmp bx, [piece_count]
    jl .sk_have
    xor bx, bx
.sk_have:
    mov [piece_index], bx
    call sync_cursor_to_piece
    jmp .after_key

.on_enter:
    cmp byte [phase], 0
    jne .enter_move

    mov ax, [cur_row]
    mov [sel_row], ax
    mov ax, [cur_col]
    mov [sel_col], ax
    mov byte [phase], 1
    call compute_legal_moves
    jmp .after_key

.enter_move:
    mov ax, [sel_row]
    cmp ax, [cur_row]
    jne .em_move
    mov ax, [sel_col]
    cmp ax, [cur_col]
    jne .em_move
    mov byte [phase], 0
    jmp .after_key
.em_move:
    call make_move
    cmp byte [winner], 0
    jne .show_win
    call build_piece_list
    mov byte [phase], 0

.after_key:
    call draw_all
    jmp game_loop

.show_win:
    call draw_all
    mov dh, STATUS_ROW
    mov dl, WIN_CONTENT_COL
    xor bh, bh
    mov ah, 2
    int 0x10
    mov si, msg_win1
    cmp byte [winner], 1
    je .print_win
    mov si, msg_win2
.print_win:
    call print_string
    xor ah, ah
    int 0x16
.quit:
    mov ax, 0x4c00 ; ah=0x4c (終了), al=0x00 (終了コード)
    int 0x21

make_move:
    mov bx, [sel_row]
    mov cx, [sel_col]
    xor dl, dl
    call set_cell ; 元のマスを空にする
    mov bx, [cur_row]
    mov cx, [cur_col]
    mov dl, [turn]
    call set_cell ; 新しいマスに置く

    mov al, 3
    sub al, [turn]
    mov [opponent], al
    mov dx, check_capture_dir
    call for_each_dir

    mov al, [opponent]
    mov [turn], al
    jmp check_win

; dx<in> routine pointer
for_each_dir:
    push ax
    push si
    mov si, dir_table
.loop:
    lodsw
    mov [dir_dr], ax
    lodsw
    mov [dir_dc], ax
    call dx
    cmp si, dir_table_end
    jb .loop
    pop si
    pop ax
    ret

check_capture_dir:
    push ax
    push bx
    push cx
    push dx
    push si

    mov bx, [cur_row]
    mov cx, [cur_col]
    xor dx, dx
.ccd_scan:
    add bx, [dir_dr]
    add cx, [dir_dc]
    cmp bx, 8
    ja .ccd_none
    cmp cx, 8
    ja .ccd_none
    call get_cell
    cmp al, [opponent]
    jne .ccd_terminator
    inc dx
    jmp .ccd_scan
.ccd_terminator:
    cmp al, [turn]
    jne .ccd_none
    test dx, dx
    je .ccd_none
    mov si, cap_by_p1
    cmp byte [turn], 1
    je .ccd_count
    mov si, cap_by_p2
.ccd_count:
    add [si], dx
    mov si, dx
    xor dl, dl
.ccd_clear:
    sub bx, [dir_dr]
    sub cx, [dir_dc]
    call set_cell
    dec si
    jnz .ccd_clear
.ccd_none:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

check_win:
    cmp word [cap_by_p1], 5
    jl .cw_chk_p2
    mov byte [winner], 1
    ret
.cw_chk_p2:
    cmp word [cap_by_p2], 5
    jl .cw_none
    mov byte [winner], 2
.cw_none:
    ret

compute_legal_moves:
    pusha
    xor di, di
.clm_clear:
    mov byte [legal_move+di], 0
    inc di
    cmp di, 81
    jl .clm_clear

    mov bx, [sel_row]
    mov cx, [sel_col]
    call legal_offset
    mov byte [di], 1

    mov dx, mark_dir
    call for_each_dir
    popa
    ret

mark_dir:
    push ax
    push bx
    push cx
    push di
    mov bx, [sel_row]
    mov cx, [sel_col]
.md_loop:
    add bx, [dir_dr]
    add cx, [dir_dc]
    cmp bx, 8
    ja .md_done
    cmp cx, 8
    ja .md_done
    call get_cell
    test al, al
    jne .md_done
    call legal_offset
    mov byte [di], 1
    jmp .md_loop
.md_done:
    pop di
    pop cx
    pop bx
    pop ax
    ret

; bx<in>  行 （0-8）
; cx<in>  列 （0-8）
; di<out> legal_move+row*9+col
legal_offset:
    imul di, bx, 9
    add di, cx
    add di, legal_move
    ret

; bx<in>  行 （0-8）
; cx<in>  列 （0-8）
; al<out> そのマスのlegal_moveの値 （0 or 1）
is_legal_cursor_move:
    push di
    call legal_offset
    mov al, [di]
    pop di
    ret

; bx<in> 行 （0-8）
; cx<in> 列 （0-8）
; al<out> マスの値 （0 = 空, 1 = P1, 2 = P2）
get_cell:
    push bx
    imul bx, bx, 9
    add bx, cx
    mov al, [board+bx]
    pop bx
    ret

; board[bx][cx] = dl
; bx&cx: 0-8
; dl<in> 書く値 （0 = 空, 1 = P1, 2 = P2）
set_cell:
    push bx
    imul bx, bx, 9
    add bx, cx
    mov [board+bx], dl
    pop bx
    ret

build_piece_list:
    pusha
    mov word [piece_count], 0
    xor bx, bx
.row:
    cmp bx, 9
    jge .done
    xor cx, cx
.col:
    cmp cx, 9
    jge .row_next
    call get_cell
    cmp al, [turn]
    jne .col_next
    mov si, [piece_count]
    shl si, 1
    mov [piece_row+si], bx
    mov [piece_col+si], cx
    inc word [piece_count]
.col_next:
    inc cx
    jmp .col
.row_next:
    inc bx
    jmp .row
.done:
    mov word [piece_index], 0
    call sync_cursor_to_piece
    popa
    ret

; cur_row/cur_colを[piece_index]番目の駒の位置にする
sync_cursor_to_piece:
    push ax
    push bx
    mov bx, [piece_index]
    shl bx, 1
    mov ax, [piece_row+bx]
    mov [cur_row], ax
    mov ax, [piece_col+bx]
    mov [cur_col], ax
    pop bx
    pop ax
    ret

draw_all:
    pusha

    mov dh, TITLE_ROW
    mov dl, WIN_CONTENT_COL
    xor bh, bh
    mov ah, 2
    int 0x10
    mov si, msg_title
    call print_string

    xor bx, bx
.da_row:
    cmp bx, 9
    jge .da_row_done
    xor cx, cx
.da_col:
    cmp cx, 9
    jge .da_col_done
    call draw_cell
    inc cx
    jmp .da_col
.da_col_done:
    inc bx
    jmp .da_row
.da_row_done:

    mov dh, STATUS_ROW
    mov dl, WIN_CONTENT_COL
    xor bh, bh
    mov ah, 2
    int 0x10
    mov si, msg_turn1
    cmp byte [turn], 1
    je .da_status
    mov si, msg_turn2
.da_status:
    call print_string
    mov si, msg_cap_p1
    call print_string
    mov ax, [cap_by_p1]
    add al, '0'
    call putc
    mov si, msg_cap_p2
    call print_string
    mov ax, [cap_by_p2]
    add al, '0'
    call putc

    mov dh, HINT_ROW
    mov dl, WIN_CONTENT_COL
    xor bh, bh
    mov ah, 2
    int 0x10
    mov si, msg_hint
    call print_string

    popa
    ret

; draw_cell: 盤のマスを1つ描画する （幅2文字）
; bx<in> 行 （0-8）
; cx<in> 列 （0-8）
draw_cell:
    pusha

    call get_cell ; al = このマスの駒

    mov dl, '.'
    mov dh, 0x08 ; empty
    cmp al, 1
    jne .dc_chk_p2
    mov dl, 'O'
    mov dh, 0x0a ; P1
    jmp .dc_have_char
.dc_chk_p2:
    cmp al, 2
    jne .dc_have_char
    mov dl, 'X'
    mov dh, 0x0c ; P2
.dc_have_char:
    and dh, 0x0f
    cmp bx, [cur_row]
    jne .dc_chk_sel
    cmp cx, [cur_col]
    jne .dc_chk_sel
    or dh, 0xf0 ; cursor
    jmp .dc_attr_done
.dc_chk_sel:
    cmp byte [phase], 0
    je .dc_attr_done
    cmp bx, [sel_row]
    jne .dc_chk_legal
    cmp cx, [sel_col]
    jne .dc_chk_legal
    or dh, 0x60 ; selecting
    jmp .dc_attr_done
.dc_chk_legal:
    call is_legal_cursor_move
    test al, al
    je .dc_attr_done
    or dh, 0x70 ; movable
.dc_attr_done:
    lea si, [BOARD_ROW+bx]
    mov di, cx
    shl di, 1
    add di, BOARD_COL

    mov ax, dx
    call putchar_at
    inc di
    mov al, ' '
    call putchar_at

    popa
    ret

; si<in> 画面の行 （絶対位置）
; di<in> 画面の列 （絶対位置）
; ax<in> (属性<<8)|文字
putchar_at:
    push bx
    imul bx, si, 80
    add bx, di
    shl bx, 1
    mov [es:bx], ax
    pop bx
    ret

%include "src/common.inc"

msg_title db "Hasami Shogi  (O = P1, X = P2)", 0
msg_turn1 db "Turn: P1 (O)", 0
msg_turn2 db "Turn: P2 (X)", 0
msg_cap_p1 db "   Captured  P1:", 0
msg_cap_p2 db "  P2:", 0
msg_hint db "L/R: choose  Enter: select  Ctrl+C: menu", 0
msg_win1 db "*** P1 WINS! *** Press a key for the menu.", 0
msg_win2 db "*** P2 WINS! *** Press a key for the menu.", 0

dir_table  dw 0, 1, 0, -1, 1, 0, -1, 0 ; (dr, dc) の組: 右, 左, 下, 上
dir_table_end:

cur_row dw 4
cur_col dw 4
phase db 0 ; 0 = 駒の選択中 （左右キー）, 1 = 移動先の選択中
sel_row dw 0
sel_col dw 0
piece_row times 9 dw 0
piece_col times 9 dw 0
piece_count dw 0
piece_index dw 0
legal_move times 9*9 db 0
turn db 1
opponent db 2
cap_by_p1 dw 0
cap_by_p2 dw 0
winner db 0 ; 0 = 対局中, それ以外 = 勝ったプレイヤー
dir_dr dw 0
dir_dc dw 0

board:
db 2,2,2,2,2,2,2,2,2
times 7*9 db 0
db 1,1,1,1,1,1,1,1,1

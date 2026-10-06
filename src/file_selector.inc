VIDEO_SEG     equ 0xb800
MAP_WIDTH     equ 19
MAP_HEIGHT    equ 11
COLS          equ 9      ; MAP_WIDTH  = 2*COLS+1
ROWS          equ 5      ; MAP_HEIGHT = 2*ROWS+1
PAGE_SIZE     equ 8      ; 1画面あたりのゴール数
GEN_RETRIES   equ 30     ; 行き止まりが足りないときの迷路再生成の上限回数

FILENAME_SIZE equ 12

TITLE_ROW   equ 0
LEGEND_ROW  equ 2
PAGE_ROW    equ 5
MAZE_ROW    equ 6
MAZE_COL    equ 2

show_maze_selector:
    call seed_rng
    mov word [current_page], 0
    mov word [origin_row], MAZE_ROW
    mov word [origin_col], MAZE_COL

    ; total_pages = ceil((VAR_COUNT + SPECIAL_COUNT) / PAGE_SIZE)
    mov ax, [VAR_COUNT]
    add ax, SPECIAL_COUNT + PAGE_SIZE - 1
    xor dx, dx
    mov cx, PAGE_SIZE
    div cx
    mov [total_pages], ax

.page_loop:
    ; ページ切り替え時は前ページのdraw_mapでes=VIDEO_SEGのまま。
    ; print_legendはVAR_TABLEを読むのにes=0が必要
    xor ax, ax
    mov es, ax

    mov ax, 3 ; テキストモード
    int 0x10

    mov dl, MAZE_COL ; x
    mov dh, TITLE_ROW ; y
    xor bh, bh
    mov ah, 2
    int 0x10
    mov si, msg_title
    call print_string

    ; page_start = current_page * PAGE_SIZE
    ; total_goals = min(PAGE_SIZE, page_start以降の残り項目数)
    imul ax, [current_page], PAGE_SIZE
    mov [page_start], ax
    mov cx, [VAR_COUNT]
    add cx, SPECIAL_COUNT
    sub cx, ax
    cmp cx, PAGE_SIZE
    jbe .count_ok
    mov cx, PAGE_SIZE
.count_ok:
    mov [total_goals], cx

    call print_legend
    call print_page_hint

    mov cx, GEN_RETRIES
.retry_gen:
    call generate_maze
    call compute_leaves
    mov ax, [leaf_count]
    cmp ax, [total_goals]
    jge .gen_ok
    loop .retry_gen
.gen_ok:
    mov ax, [leaf_count]
    cmp ax, [total_goals]
    jge .no_clamp
    mov [total_goals], ax
.no_clamp:
    call place_goals

    mov word [player_row], 1
    mov word [player_col], 1

    mov ax, VIDEO_SEG
    mov es, ax
    call draw_map

.game_loop:
    call draw_player
    xor ah, ah
    int 0x16

    cmp al, 'n'
    je .next_page
    cmp al, 'N'
    je .next_page
    cmp al, 'p'
    je .prev_page
    cmp al, 'P'
    je .prev_page
    cmp ah, 0x3b ; F1
    je .show_help

    call try_step
    jc .game_loop

    cmp al, '1'
    jl .normal_move
    cmp al, [max_goal_char]
    jg .normal_move

    xor ah, ah
    sub al, '1' ; ax = ゴール番号
    add ax, [page_start]
    mov [VAR_SELECTED], ax
    RESET_SEGMENTS
    jmp dispatch_selection

.normal_move:
    call move_player
    jmp .game_loop

.next_page:
    mov ax, [current_page]
    inc ax
    cmp ax, [total_pages]
    jge .game_loop ; 最後のページなら無視
    mov [current_page], ax
    jmp .page_loop

.prev_page:
    mov ax, [current_page]
    test ax, ax
    je .game_loop ; 最初のページなら無視
    dec ax
    mov [current_page], ax
    jmp .page_loop

.show_help:
    push es
    xor ax, ax
    mov es, ax
    xor bx, bx
.loop:
    cmp bx, [VAR_COUNT]
    jge .not_found
    mov si, bx
    shl si, 1
    mov di, [VAR_TABLE+si]
    push bx
    mov si, reame_txt_string
    mov cx, FILENAME_SIZE-1
    repe cmpsb
    pop bx
    je .found
    inc bx
    jmp .loop
.found:
    mov [VAR_SELECTED], bx
    pop es
    RESET_SEGMENTS
    jmp dispatch_selection
.not_found:
    pop es
    jmp .game_loop

print_legend:
    pusha
    xor di, di
.loop:
    cmp di, [total_goals]
    jge .done

    ; LEGEND_ROW + index/3
    mov ax, di
    mov cl, 3
    div cl
    mov dh, al
    add dh, LEGEND_ROW
    ; MAZE_COL + (index % 3) * 26
    mov al, ah
    mov cl, 26
    mul cl
    add al, MAZE_COL
    mov dl, al
    xor bh, bh
    mov ah, 2
    int 0x10

    mov ax, di
    add al, '1'
    call putc
    mov al, ':'
    call putc

    mov ax, di
    add ax, [page_start]
    cmp ax, [VAR_COUNT]
    jae .special

    mov bx, ax
    shl bx, 1
    mov bx, [VAR_TABLE+bx]
    call print_flat_name
    jmp .after_name

.special:
    sub ax, [VAR_COUNT]
    mov bx, ax
    shl bx, 1
    mov si, [special_names+bx]
    call print_string

.after_name:
    mov al, ' '
    call putc
    inc di
    jmp .loop
.done:
    popa
    ret

; 2ページ以上ある場合現在ページと移動方法を表示する
print_page_hint:
    pusha
    mov ax, [total_pages]
    cmp ax, 1
    jbe .done

    mov dh, PAGE_ROW
    mov dl, MAZE_COL
    xor bh, bh
    mov ah, 2
    int 0x10

    mov si, msg_page
    call print_string

    mov ax, [current_page]
    inc ax
    call print_number

    mov al, '/'
    call putc

    mov ax, [total_pages]
    call print_number

    mov si, msg_page_hint
    call print_string

.done:
    popa
    ret

; ax<in> 表示する数
print_number:
    push ax
    push bx
    push cx
    push dx
    xor cx, cx
    mov bx, 10
.divloop:
    xor dx, dx
    div bx
    push dx
    inc cx
    test ax, ax
    jnz .divloop
.printloop:
    pop dx
    add dl, '0'
    mov al, dl
    call putc
    loop .printloop
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; bx<in> ディレクトリエントリへのポインタ
print_flat_name:
    push ax
    push bx
    push cx
    mov cx, DirEntry.ext - DirEntry.name
    call print_field
    add bx, DirEntry.ext
    cmp byte [es:bx], ' '
    je .no_extension
    mov al, '.'
    call putc
    mov cx, DirEntry.attr - DirEntry.ext
    call print_field
.no_extension:
    pop cx
    pop bx
    pop ax
    ret

; bx<in> フィールドへのポインタ
; cx<in> フィールドの長さ
print_field:
    push ax
    push bx
    push cx
    push si
    mov si, bx
    add si, cx
.trim:
    jcxz .done
    dec si
    cmp byte [es:si], ' '
    jne .print
    loop .trim
    jmp .done
.print:
    mov al, [es:bx]
    call putc
    inc bx
    loop .print
.done:
    pop si
    pop cx
    pop bx
    pop ax
    ret

compute_leaves:
    pusha
    mov word [leaf_count], 0
    mov byte [test_row], 0
.row:
    mov byte [test_col], 0
.col:
    call cell_grid_offset
    cmp di, maze_map + MAP_WIDTH + 1
    je .next ; スタートのセルは飛ばす

    xor ax, ax ; ax = 開いた隣接の数
    cmp byte [di-1], '.'
    jne .no_left
    inc ax
.no_left:
    cmp byte [di+1], '.'
    jne .no_right
    inc ax
.no_right:
    cmp byte [di-MAP_WIDTH], '.'
    jne .no_up
    inc ax
.no_up:
    cmp byte [di+MAP_WIDTH], '.'
    jne .no_down
    inc ax
.no_down:
    cmp ax, 1
    jne .next

    mov bx, [leaf_count]
    shl bx, 1
    mov [leaf_pos+bx], di
    inc word [leaf_count]

.next:
    inc byte [test_col]
    cmp byte [test_col], COLS
    jb .col
    inc byte [test_row]
    cmp byte [test_row], ROWS
    jb .row
    popa
    ret

place_goals:
    pusha
    mov byte [max_goal_char], '0' ; total_goalsが0でも問題ない初期値
    xor bx, bx
.loop:
    cmp bx, [total_goals]
    jge .ok

    call next_random
    mov cx, [leaf_count]
    sub cx, bx ; cx = 残りの候補数
    xor dx, dx
    div cx ; dx = 0 ~ cx の乱数
    add dx, bx
    mov si, bx
    shl si, 1
    mov di, dx
    shl di, 1
    mov ax, [leaf_pos+si]
    xchg ax, [leaf_pos+di]
    mov [leaf_pos+si], ax

    mov di, ax
    mov al, bl
    add al, '1'
    mov [di], al
    mov [max_goal_char], al

    inc bx
    jmp .loop
.ok:
    popa
    ret

msg_title       db "Reach the number to open   F1: Help", 0
msg_page        db "Page ", 0
msg_page_hint   db "   N: next page   P: previous page", 0
reame_txt_string     db "README  TXT" ; NULL不要
str_shutdown    db "SHUTDOWN", 0
str_reboot      db "REBOOT", 0
special_names   dw str_shutdown, str_reboot

total_pages     dw 0
current_page    dw 0
page_start      dw 0
total_goals     dw 0
max_goal_char   db '0' ; ascii

leaf_pos        times COLS*ROWS dw 0
leaf_count      dw 0

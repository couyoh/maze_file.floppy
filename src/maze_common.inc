%include "src/common.inc"

seed_rng:
    push ax
    push cx
    push dx
    xor ax, ax
    int 0x1a ; ah=0: システムタイマ読み出し -> cx:dx
    mov [rng_state], dx
    pop dx
    pop cx
    pop ax
    ret

; https://stackoverflow.com/a/4070966
; ax<out> random number
next_random:
    push dx
    mov ax, [rng_state]
    mov dx, 25173
    mul dx
    add ax, 13849
    mov [rng_state], ax
    pop dx
    ret

generate_maze:
    pusha
    mov di, maze_map
    mov cx, MAP_WIDTH*MAP_HEIGHT
.fill_walls:
    mov byte [di], '#'
    inc di
    loop .fill_walls

    mov byte [cell_row_stack], 0
    mov byte [cell_col_stack], 0
    mov word [stack_ptr], 1
    mov byte [maze_map + MAP_WIDTH + 1], '.' ; セル（0,0）を訪問済みにする

.carve_loop:
    cmp word [stack_ptr], 0
    je .carve_done

    mov bx, [stack_ptr]
    dec bx
    mov al, [cell_row_stack+bx]
    mov [cur_row], al
    mov al, [cell_col_stack+bx]
    mov [cur_col], al

    ; 現在のセルの未訪問の隣接方向（0=上,1=下,2=左,3=右）を
    ; valid_dirsに集める
    xor si, si ; valid_dirsへの書き込み位置 （バイト）
    xor bx, bx ; 方向番号 0..3
.dir_loop:
    cmp bx, 4
    jge .dirs_done

    mov al, [cur_row]
    add al, [dir_dr+bx]
    cmp al, ROWS-1
    ja .dir_next
    mov [test_row], al

    mov al, [cur_col]
    add al, [dir_dc+bx]
    cmp al, COLS-1
    ja .dir_next
    mov [test_col], al

    call cell_grid_offset ; di = (test_row,test_col) のmaze_map上の位置
    cmp byte [di], '#'
    jne .dir_next ; 訪問済み

    mov [valid_dirs+si], bx
    add si, 2
.dir_next:
    inc bx
    jmp .dir_loop

.dirs_done:
    test si, si
    jne .have_dirs
    dec word [stack_ptr] ; 行き止まり -> 1つ戻る
    jmp .carve_loop

.have_dirs:
    call next_random
    xor dx, dx
    mov cx, si
    shr cx, 1 ; cx = 候補の方向の数
    div cx ; dx = 0, cxの乱数
    shl dx, 1
    mov si, dx
    mov bx, [valid_dirs+si] ; bx = 選んだ方向番号

    mov al, [cur_row]
    add al, [dir_dr+bx]
    mov [test_row], al
    mov al, [cur_col]
    add al, [dir_dc+bx]
    mov [test_col], al

    ; 1. 隣のセルを訪問済みにする
    ; 2. 現在のセルとの間の壁 （隣から1マス戻った位置） を通路にする
    call cell_grid_offset
    mov byte [di], '.'
    shl bx, 1
    sub di, [dir_offset+bx]
    mov byte [di], '.'

    mov bx, [stack_ptr]
    mov al, [test_row]
    mov [cell_row_stack+bx], al
    mov al, [test_col]
    mov [cell_col_stack+bx], al
    inc word [stack_ptr]
    jmp .carve_loop

.carve_done:
    mov byte [maze_map + MAP_WIDTH + 1], 'S'
    popa
    ret

; セル（test_row,test_col）のmaze_map上のアドレスを返す
; マス目では （2*test_row+1, 2*test_col+1）
; di<out> そのセルを指すmaze_map内のポインタ
cell_grid_offset:
    push ax
    mov al, [test_row]
    cbw
    imul di, ax, 2*MAP_WIDTH
    mov al, [test_col]
    cbw
    shl ax, 1
    add di, ax
    add di, maze_map + MAP_WIDTH + 1
    pop ax
    ret

; maze_mapのタイルを1つ読む
; si<in>  マップの行
; di<in>  マップの列
; al<out> タイルの文字
get_map_char:
    push bx
    imul bx, si, MAP_WIDTH
    add bx, di
    mov al, [maze_map+bx]
    pop bx
    ret

; 矢印キーで移動したときの移動先タイルを調べる
; ah<in>  押されたキーのBIOSスキャンコード
; bx<out> 移動先の行
; cx<out> 移動先の列
; al<out> (bx,cx) のタイル
try_step:
    mov bx, [player_row]
    mov cx, [player_col]
    cmp ah, 0x48             ; 上
    jne .chk_down
    dec bx
    jmp .have_step
.chk_down:
    cmp ah, 0x50             ; 下
    jne .chk_left
    inc bx
    jmp .have_step
.chk_left:
    cmp ah, 0x4b             ; 左
    jne .chk_right
    dec cx
    jmp .have_step
.chk_right:
    cmp ah, 0x4d             ; 右
    jne .blocked
    inc cx
.have_step:
    ; 外周は必ず壁なので、1歩でmaze_mapの外に出ることはない
    push si
    push di
    mov si, bx
    mov di, cx
    call get_map_char
    pop di
    pop si
    cmp al, '#'
    je .blocked
    clc
    ret
.blocked:
    stc
    ret

; 元のタイルからプレイヤーを消し、座標を更新する
; (新しい位置への描画はdraw_playerが行う)
; bx<in> 移動先の行
; cx<in> 移動先の列
move_player:
    push si
    push di
    mov si, [player_row]
    mov di, [player_col]
    call draw_map_cell
    mov [player_row], bx
    mov [player_col], cx
    pop di
    pop si
    ret

; maze_mapの全タイルを描画する
draw_map:
    push si
    push di
    xor si, si
.row:
    cmp si, MAP_HEIGHT
    jge .row_done
    xor di, di
.col:
    cmp di, MAP_WIDTH
    jge .col_done
    call draw_map_cell
    inc di
    jmp .col
.col_done:
    inc si
    jmp .row
.row_done:
    pop di
    pop si
    ret

; maze_mapのタイルを1つ色付きで描画する
; si<in> マップの行
; di<in> マップの列
draw_map_cell:
    push ax
    call get_map_char
    mov ah, 0x0f              ; 既定: 白
    cmp al, '#'
    jne .not_wall
    mov ah, 0x08               ; 壁: 暗い灰色
    jmp .have_attr
.not_wall:
    cmp al, '.'
    je .have_attr                ; 通路: 既定色
    mov ah, 0x0e                  ; スタート・ゴール: 黄色
.have_attr:
    call putchar_at
    pop ax
    ret

; 現在のプレイヤー位置に'@'を描画する
draw_player:
    push si
    push di
    push ax
    mov si, [player_row]
    mov di, [player_col]
    mov ax, 0x0f40 ; 属性 0x0f, 文字 '@'
    call putchar_at
    pop ax
    pop di
    pop si
    ret

; si<in> マップの行 （迷路内の相対位置）
; di<in> マップの列 （迷路内の相対位置）
; ax<in> (属性<<8)|文字
putchar_at:
    push bx
    mov bx, si
    add bx, [origin_row]
    imul bx, bx, 80
    add bx, di
    add bx, [origin_col]
    shl bx, 1
    mov [es:bx], ax
    pop bx
    ret

origin_row dw 0
origin_col dw 0
player_row dw 0
player_col dw 0

rng_state       dw 0
stack_ptr       dw 0
cur_row         db 0
cur_col         db 0
test_row        db 0
test_col        db 0
dir_dr          db -1, 1, 0, 0     ; 上, 下, 左, 右
dir_dc          db 0, 0, -1, 1
dir_offset      dw -MAP_WIDTH, MAP_WIDTH, -1, 1   ; 同じ方向をmaze_map上の移動量で表したもの
valid_dirs      times 4 dw 0
cell_row_stack  times COLS*ROWS db 0
cell_col_stack  times COLS*ROWS db 0

maze_map        times MAP_WIDTH*MAP_HEIGHT db '#'

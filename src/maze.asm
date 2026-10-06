bits 16
%include "src/layout.inc"
org 0x100

VIDEO_SEG   equ 0xb800
MAP_WIDTH   equ 19
MAP_HEIGHT  equ 11
COLS        equ 9
ROWS        equ 5

MAZE_ROW    equ WIN_CONTENT_ROW + 2
MAZE_COL    equ WIN_CONTENT_COL + (WIN_CONTENT_WIDTH - MAP_WIDTH) / 2

start:
    call seed_rng
    call generate_maze
    mov byte [maze_map + (2*(ROWS-1)+1)*MAP_WIDTH + (2*(COLS-1)+1)], 'G'

    ; 枠はstage2が描画済み。内側だけに描く
    mov word [origin_row], MAZE_ROW
    mov word [origin_col], MAZE_COL

    mov ax, VIDEO_SEG
    mov es, ax

    mov dh, MAZE_ROW - 2 ; タイトルは迷路の2行上
    mov dl, MAZE_COL
    xor bh, bh
    mov ah, 0x02
    int 0x10
    mov si, msg_title_menu
    call print_string

    ; スタート'S'は常にセル（0,0）
    mov word [player_row], 1
    mov word [player_col], 1

    call draw_map

.game_loop:
    call draw_player
    xor ah, ah
    int 0x16

    cmp al, 3 ; Ctrl+C -> メニューへ戻る
    je .quit

    call try_step ; bx/cx = 移動先の座標, al = そのタイル
    jc .game_loop ; 矢印キー以外、または壁
    call move_player
    cmp al, 'G'
    jne .game_loop

    ; ゴール到達
    call draw_player
    mov dh, MAZE_ROW + MAP_HEIGHT + 1
    mov dl, MAZE_COL
    xor bh, bh
    mov ah, 0x02
    int 0x10
    mov si, msg_win
    call print_string

    xor ah, ah ; キー入力を待ってメニューへ戻る
    int 0x16
.quit:
    mov ax, 0x4c00 ; ah=0x4c（終了）, al=0x00（終了コード）
    int 0x21

msg_title_menu db "Arrows: move Ctrl+C: menu", 0
msg_win        db "*** CLEAR! *** Press a key to continue.", 0

%include "src/maze_common.inc"

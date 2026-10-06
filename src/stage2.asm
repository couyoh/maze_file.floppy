bits 16
%include "src/layout.inc"
org STAGE2_ADDR

%macro RESET_SEGMENTS 0
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7c00
    sti
%endmacro

init:
    RESET_SEGMENTS
.install_hooks:
    ; .COMの終了システムコールで迷路エクスプローラに戻したいため int 0x20 と int 0x21 をメニューへ戻るハンドラに差し替える
    mov ax, reset_then_menu
    mov bx, cs
    ; int 0x20 (0x4 * 0x20)
    mov [es:0x80], ax
    mov [es:0x82], bx
    ; int 0x21 (0x4 * 0x21)
    mov [es:0x84], ax
    mov [es:0x86], bx

.load_root_and_table:
    mov ax, ROOT_DIR_LBA
    mov bx, ROOT_BUF
    mov cx, ROOT_DIR_SECTORS
    call read_sectors

    mov si, ROOT_BUF
    mov word [VAR_COUNT], 0
    mov di, VAR_TABLE

    mov cx, ROOT_ENTRIES
.scan:
    cmp byte [si+DirEntry.name], 0
    je .scan_done
    ; 削除済みファイルは先頭が0xe5なので飛ばす
    cmp byte [si+DirEntry.name], 0xe5
    je .scan_next
    test byte [si+DirEntry.attr], ATTR_VOLUME_ID
    jnz .scan_next
    mov [di], si
    add di, 2
    inc word [VAR_COUNT]
.scan_next:
    add si, DirEntry_size
    loop .scan
.scan_done:
    mov word [VAR_SELECTED], 0

reset_then_menu:
    RESET_SEGMENTS
    jmp show_maze_selector

; VAR_SELECTEDの項目を実行・表示する
dispatch_selection:
    mov ax, [VAR_SELECTED]
    cmp ax, [VAR_COUNT]
    jae .special_chosen

    mov bx, ax
    shl bx, 1
    mov si, [VAR_TABLE+bx]    ; si -> 選んだディレクトリエントリ

    test byte [si+DirEntry.attr], ATTR_DIRECTORY
    jnz view_folder

    ; .COMだけ実行する。それ以外はテキストとして表示
    cmp word [si+DirEntry.ext], 'CO'
    jne view_text
    cmp byte [si+DirEntry.ext+2], 'M'
    jne view_text
    call draw_window
    jmp run_entry

.special_chosen:
    sub ax, [VAR_COUNT]
    jz shutdown
    jmp reboot

; si<in> 実行する32バイトのディレクトリエントリへのポインタ
run_entry:
    mov bx, EXEC_ADDR
    call load_file

    mov ax, EXEC_SEGMENT
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0xfffe
    jmp EXEC_SEGMENT:0x100

; si<in> 読み込む32バイトのディレクトリエントリへのポインタ
; bx<in> 読み込み先 （es:bx）
load_file:
    pusha
    push bx
    mov ax, RESERVED_SECTORS
    mov bx, FAT_BUF
    mov cx, SECTORS_PER_FAT
    call read_sectors
    pop bx

    mov si, [si+DirEntry.cluster_lo]  ; si = 現在のクラスタ
.next_cluster:
    cmp si, 0x0ff8
    jae .done

    ; lba = DATA_LBA + (cluster - 2) * SECTORS_PER_CLUSTER
    lea ax, [si-2]
    mov cx, SECTORS_PER_CLUSTER
    mul cx
    add ax, DATA_LBA
    call read_sectors

    mov ax, si
    call get_fat_entry
    mov si, ax
    jmp .next_cluster
.done:
    popa
    ret

; si<in> 選んだディレクトリエントリへのポインタ
view_text:
    call draw_window
    call draw_hint

    mov ax, [si+DirEntry.size]
    cmp ax, TEXT_BUF_MAX
    jbe .size_ok
    mov ax, TEXT_BUF_MAX
.size_ok:
    mov [text_len], ax

    mov bx, TEXT_BUF
    call load_file

    mov word [line_count], 0
    mov di, LINE_TABLE
    xor si, si
.build_lines:
    cmp si, [text_len]
    jae .build_done
    cmp word [line_count], MAX_LINES
    jae .build_done
    mov [di], si
    add di, 2
    inc word [line_count]
    xor cx, cx
.scan_line:
    cmp si, [text_len]
    jae .build_lines
    mov al, [TEXT_BUF+si]
    inc si
    cmp al, `\n`
    je .build_lines
    cmp al, `\r`
    je .scan_line
    inc cx
    cmp cx, WIN_CONTENT_WIDTH
    jb .scan_line
    jmp .build_lines            ; 折り返し -- ここから新しい行
.build_done:

    mov word [scroll], 0

.redraw:
    call render_text
.text_loop:
    xor ah, ah
    int 0x16
    cmp al, 3                    ; Ctrl+C
    je .back_to_menu
    cmp ah, 0x48                ; 上矢印
    jne .chk_txt_down
    cmp word [scroll], 0
    je .text_loop
    dec word [scroll]
    jmp .redraw
.chk_txt_down:
    cmp ah, 0x50                ; 下矢印
    jne .text_loop
    mov ax, [line_count]
    sub ax, WIN_CONTENT_HEIGHT
    jle .text_loop               ; 全行が画面に収まっている
    cmp [scroll], ax
    jae .text_loop
    inc word [scroll]
    jmp .redraw
.back_to_menu:
    jmp show_maze_selector

; フォルダ表示は未実装。
; 未対応メッセージを出し、Ctrl+Cでメニューに戻る
; si<in> 選んだディレクトリエントリへのポインタ （未使用）
view_folder:
    call draw_window
    call draw_hint

    mov dh, WIN_CONTENT_ROW
    mov dl, WIN_CONTENT_COL
    xor bh, bh
    mov ah, 2
    int 0x10
    mov si, msg_is_folder
    call print_string

.vf_loop:
    xor ah, ah
    int 0x16
    cmp al, 3 ; Ctrl+C
    jne .vf_loop
    jmp show_maze_selector

msg_is_folder db "Viewing folders is not supported.", 0

; 読み込んだテキストを[scroll]行目からWIN_CONTENT_HEIGHT行分、ウィンドウ内に描画する
render_text:
    push es
    pusha
    mov ax, 0xb800
    mov es, ax

    mov bx, [scroll] ; bx = 現在の行番号
    xor dx, dx ; dx = 現在の画面行 （0始まり）
.render_row:
    cmp dx, WIN_CONTENT_HEIGHT
    jae .render_done

    mov bp, [text_len]
    cmp bx, [line_count]
    jae .start_row
    mov si, bx
    shl si, 1
    mov bp, [LINE_TABLE+si] ; bp = この行のTEXT_BUF内開始位置
.start_row:
    mov si, WIN_CONTENT_ROW
    add si, dx
    mov di, WIN_CONTENT_COL
    mov cx, WIN_CONTENT_WIDTH
.draw_char:
    jcxz .next_row
    cmp bp, [text_len]
    jae .pad_rest
    mov al, [TEXT_BUF+bp]
    inc bp
    cmp al, `\r`
    je .draw_char
    cmp al, `\n`
    je .pad_rest
    call wputc
    inc di
    dec cx
    jmp .draw_char
.pad_rest:
    jcxz .next_row
    mov al, ' '
    call wputc
    inc di
    loop .pad_rest

.next_row:
    inc bx
    inc dx
    jmp .render_row
.render_done:
    popa
    pop es
    ret

text_len   dw 0
line_count dw 0
scroll     dw 0

draw_hint:
    push es
    pusha
    mov ax, 0xb800
    mov es, ax
    mov si, WIN_ROW + WIN_HEIGHT - 1
    mov di, WIN_COL + 2
    mov bp, msg_hint
.dh_loop:
    mov al, [bp]
    test al, al
    je .dh_done
    call wputc
    inc di
    inc bp
    jmp .dh_loop
.dh_done:
    popa
    pop es
    ret

msg_hint db " Ctrl+C: menu ", 0

; ax<in>  クラスタ番号
; ax<out> FAT[クラスタ] の値
get_fat_entry:
    push bx
    push cx
    push dx
    mov bx, ax
    mov cx, ax
    shr cx, 1
    add bx, cx ; bx = floor(cluster * 3 / 2)
    mov dx, [bx+FAT_BUF]
    test al, 1
    jz .even
    shr dx, 4
    jmp .done
.even:
    and dx, 0x0fff
.done:
    mov ax, dx
    pop dx
    pop cx
    pop bx
    ret

draw_window:
    push es
    pusha
    mov ax, 0x0003
    int 0x10
    mov ax, 0xb800
    mov es, ax

    ; 上枠
    mov si, WIN_ROW
    mov di, WIN_COL
    mov al, 0xda ; 左上の角
    call wputc
    mov cx, WIN_WIDTH - 2
.top_line:
    inc di
    mov al, 0xc4 ; 横線
    call wputc
    loop .top_line
    inc di
    mov al, 0xbf ; 右上の角
    call wputc

    ; 左右の枠 + 内側の消去
    mov dx, WIN_CONTENT_HEIGHT
    mov si, WIN_CONTENT_ROW
.row_loop:
    mov di, WIN_COL
    mov al, 0xb3 ; 縦線
    call wputc
    mov cx, WIN_CONTENT_WIDTH
    mov di, WIN_CONTENT_COL
.blank_loop:
    mov al, ' '
    call wputc
    inc di
    loop .blank_loop
    mov al, 0xb3
    call wputc
    inc si
    dec dx
    jnz .row_loop

    ; 下枠
    mov si, WIN_ROW + WIN_HEIGHT - 1
    mov di, WIN_COL
    mov al, 0xc0 ; 左下の角
    call wputc
    mov cx, WIN_WIDTH - 2
.bottom_line:
    inc di
    mov al, 0xc4
    call wputc
    loop .bottom_line
    inc di
    mov al, 0xd9 ; 右下の角
    call wputc

    popa
    pop es
    ret

; al<in> 書く文字
; si<in> 画面の行
; di<in> 画面の列
wputc:
    push ax
    push bx
    imul bx, si, 80
    add bx, di
    shl bx, 1
    mov ah, 0x07
    mov [es:bx], ax
    pop bx
    pop ax
    ret

; 連続したセクタを1つずつ読む （CHS）
; ax<in>  最初に読むセクタのLBA
; bx<in>  読み込み先 （es:bx）
; cx<in>  読むセクタ数
; ax<out> 最後に読んだセクタの次のLBA
; bx<out> 最後に読んだバイトの次の位置
read_sectors:
    push ax
    push cx
    xor dx, dx
    div word [SECTORS_PER_TRACK]
    inc dx
    mov cl, dl
    xor dx, dx
    div word [NUM_HEADS]
    mov dh, dl
    mov ch, al
    mov dl, [DRIVE_NUMBER]
    mov ax, 0x0201 ; ah=0x02（読み込み）, al=1セクタ
    int 0x13
    jc .disk_error
    pop cx
    pop ax
    inc ax
    add bx, SECTOR_SIZE
    loop read_sectors
    ret
.disk_error:
    mov si, msg_disk_error
    jmp print_and_hlt

%include "src/file_selector.inc"
%include "src/maze_common.inc"

; ACPIの実装が面倒なのでQEMU、Bochs、VirtualBoxのみ対応
; https://wiki.osdev.org/Shutdown

shutdown:
    mov dx, 0x604  ; QEMU
    mov ax, 0x2000
    out dx, ax
    mov dx, 0xb004 ; Bochs
    out dx, ax
    mov dx, 0x4004 ; VirtualBox
    mov ax, 0x3400
    out dx, ax
    mov si, msg_shutdown_failed

; メッセージを表示して停止する
; si<in> NUL終端メッセージへのポインタ
print_and_hlt:
    call print_string
    cli
    hlt
    jmp $

; https://wiki.osdev.org/Reboot
reboot:
    cli
.loop:
    in al, 0x64
    test al, 1 << 1
    jnz .loop
    mov al, 0xfe
    out 0x64, al
    hlt ; 再起動できなかった場合は停止
    jmp $

msg_disk_error  db `Disk read error\r\n`, 0
msg_shutdown_failed db `Shutdown is only supported on QEMU, Bochs, and VirtualBox.\r\n`, 0

times (STAGE2_SECTORS*SECTOR_SIZE) - ($-$$) db 0

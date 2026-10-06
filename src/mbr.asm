bits 16
org 0x7c00

%include "src/layout.inc"

; 参考:
; https://en.wikipedia.org/wiki/Design_of_the_FAT_file_system#Boot_Sector
; https://msdn.microsoft.com/en-us/windows/hardware/gg463080.aspx
jmp short start ; 2バイト
nop

; 値はmkfs.vfatの出力に合わせている
BS_OEMName     times 8 db ' '
BPB_BytsPerSec dw SECTOR_SIZE
BPB_SecPerClus db SECTORS_PER_CLUSTER
BPB_RsvdSecCnt dw RESERVED_SECTORS
BPB_NumFATs    db NUM_FATS
BPB_RootEntCnt dw ROOT_ENTRIES
BPB_TotSec16   dw TOTAL_SECTORS
BPB_Media      db MEDIA_DESCRIPTOR
BPB_FATSz16    dw SECTORS_PER_FAT
BPB_SecPerTrk  dw 18
BPB_NumHeads   dw 2
BPB_HiddSec    dd 0
BPB_TotSec32   dd 0
BS_DrvNum      db 0
BS_Reserved1   db 0
BS_BootSig     db 0x29
BS_VolID       dd 0x12345678
BS_VolLab      times 11 db ' '
BS_FilSysType  times 8 db ' '

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7c00
    sti

    mov [BS_DrvNum], dl

    mov ax, 1                  ; stage2の先頭セクタのLBA
    mov bx, STAGE2_ADDR
    mov cx, STAGE2_SECTORS
.load_stage2:
    call read_sector
    inc ax
    add bx, [BPB_BytsPerSec]
    loop .load_stage2

    jmp STAGE2_ADDR

; 1セクタ読む （LBA→CHS変換してint 0x13）
; ax<in> 読むセクタのLBA
; bx<in> 読み込み先 （es:bx）
read_sector:
    pusha
    xor dx, dx
    div word [BPB_SecPerTrk] ; ax = LBA / トラックあたりセクタ数, dx = 余り
    inc dx
    mov cl, dl               ; セクタ番号 （1始まり）
    xor dx, dx
    div word [BPB_NumHeads]  ; ax = シリンダ, dx = ヘッド
    mov dh, dl               ; ヘッド
    mov ch, al               ; シリンダ
    mov dl, [BS_DrvNum]      ; ドライブ番号
    ; mov ah, 0x02 ; ディスク読み込み
    ; mov al, 1    ; 1セクタ
    mov ax, 0x201
    int 0x13
    jc .disk_error
    popa
    ret
.disk_error:
    mov si, msg_disk_error
    call print_string
    cli
    hlt
    jmp $

%include "src/common.inc"

msg_disk_error  db `Disk read error\r\n`, 0

times 510-($-$$) db 0
db 0x55, 0xaa

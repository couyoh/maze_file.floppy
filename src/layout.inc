
%define ATTR_VOLUME_ID 0x08
%define ATTR_DIRECTORY 0x10

; 0x0000 - 0x03FF IVT
; 0x0400 - 0x04FF BDA
STAGE2_ADDR      equ 0x0800 ; 0x800 + (SECTOR_SIZE * STAGE2_SECTORS) = 0x1800
STAGE2_SECTORS   equ 8

; bss
VAR_SELECTED     equ 0x2006 ; word: 選択中の項目番号
VAR_COUNT        equ 0x2008 ; word: VAR_TABLE内の実ファイル数
VAR_TABLE        equ 0x200a ; word[]: 32バイトのディレクトリエントリへのフラットポインタ
LINE_TABLE       equ 0x2e00 ; 最大MAX_LINES個のword: 各行のTEXT_BUF内開始オフセット

FAT_BUF          equ 0x3000 ; 最大9セクタ （4608バイト）
ROOT_BUF         equ 0x5000 ; 最大14セクタ （7168バイト）
TEXT_BUF         equ 0x7000 ; .TXTファイルの中身 （最大TEXT_BUF_MAXバイト）
TEXT_BUF_MAX     equ 2048
STAGE1_ADDR      equ 0x7c00
EXEC_ADDR        equ 0x9000 ; 選択したファイルを読み込む物理アドレス

MAX_LINES        equ 200

; BPB
SECTOR_SIZE         equ 512 ; BPB_BytsPerSec
SECTORS_PER_CLUSTER equ 1 ; BPB_SecPerClus
RESERVED_SECTORS    equ STAGE2_SECTORS + 1 ; BPB_RsvdSecCnt (mbr + stage2)
NUM_FATS            equ 2 ; BPB_NumFATs
ROOT_ENTRIES        equ 224  ; BPB_RootEntCnt
SECTORS_PER_FAT     equ 9 ; BPB_FATSz16 -- FAT1つあたりのセクタ数
TOTAL_SECTORS       equ 2880 ; BPB_TotSec16 -- 1.44MBイメージ全体
MEDIA_DESCRIPTOR    equ 0xF0 ; BPB_Media。FAT[0]の下位バイトにも使う

BPB_OFFSET          equ STAGE1_ADDR + 11
SECTORS_PER_TRACK   equ BPB_OFFSET + 13
NUM_HEADS           equ BPB_OFFSET + 15
DRIVE_NUMBER        equ BPB_OFFSET + 25

struc DirEntry
    .name:       resb 8 ; 8.3形式のファイル名 （空白埋め）
                        ; .name[0]==0x00: ディレクトリの終端
                        ; .name[0]==0xE5: 削除済み
    .ext:        resb 3 ; 8.3形式の拡張子 （空白埋め）
    .attr:       resb 1 ; 属性
    .reserved:   resb 1
    .ctime_ms:   resb 1 ; 作成時刻 （0.1秒単位）
    .ctime:      resw 1 ; 作成時刻
    .cdate:      resw 1 ; 作成日
    .adate:      resw 1 ; 最終アクセス日
    .cluster_hi: resw 1 ; unused
    .mtime:      resw 1 ; 最終更新時刻
    .mdate:      resw 1 ; 最終更新日
    .cluster_lo: resw 1 ; unused
    .size:       resd 1 ; ファイルサイズ （バイト）
endstruc

ROOT_DIR_SECTORS equ (ROOT_ENTRIES*DirEntry_size + SECTOR_SIZE - 1) / SECTOR_SIZE
ROOT_DIR_LBA     equ RESERVED_SECTORS + NUM_FATS*SECTORS_PER_FAT
DATA_LBA         equ ROOT_DIR_LBA + ROOT_DIR_SECTORS ; クラスタ2の先頭セクタ

; EXEC_SEGMENT*16 + 0x100 == EXEC_ADDR
EXEC_SEGMENT  equ 0x08f0

SPECIAL_COUNT equ 2 ; SHUTDOWN, REBOOT

WIN_ROW            equ 4
WIN_COL            equ 17
WIN_WIDTH          equ 45 ; 枠を含む
WIN_HEIGHT         equ 17 ; 枠を含む
WIN_CONTENT_ROW    equ WIN_ROW + 1
WIN_CONTENT_COL    equ WIN_COL + 1
WIN_CONTENT_WIDTH  equ WIN_WIDTH - 2
WIN_CONTENT_HEIGHT equ WIN_HEIGHT - 2

%include "src/mbr.asm"
incbin "build/stage2.bin"

%macro FATENTRY 1
    %if (fat_entry_pos % 2) == 0
        %assign fat_entry_pending (%1)
    %else
        db (fat_entry_pending) & 0xFF
        db ((fat_entry_pending >> 8) & 0x0F) | (((%1) & 0x0F) << 4)
        db ((%1) >> 4) & 0xFF
    %endif
    %assign fat_entry_pos fat_entry_pos + 1
%endmacro

%macro FAT_TABLE 0
%%start:
db MEDIA_DESCRIPTOR, 0xff, 0xff ; クラスタ0, 1: 予約
%assign fat_entry_pos 0
FATENTRY 0            ; クラスタ 2:  空き
FATENTRY 4            ; クラスタ 3:  MAZE.COM    -> 4
FATENTRY 5            ; クラスタ 4:  MAZE.COM    -> 5
FATENTRY 0xfff        ; クラスタ 5:  MAZE.COM    終端
FATENTRY 7            ; クラスタ 6:  README.TXT  -> 7
FATENTRY 8            ; クラスタ 7:  README.TXT  -> 8
FATENTRY 9            ; クラスタ 8:  README.TXT  -> 9
FATENTRY 0xfff        ; クラスタ 9:  README.TXT  終端
FATENTRY 11           ; クラスタ 10: HASAMI.COM  -> 11
FATENTRY 12           ; クラスタ 11: HASAMI.COM  -> 12
FATENTRY 13           ; クラスタ 12: HASAMI.COM  -> 13
FATENTRY 0xfff        ; クラスタ 13: HASAMI.COM  終端
times (SECTORS_PER_FAT*SECTOR_SIZE) - ($-%%start) db 0
%endmacro

fat1: FAT_TABLE
fat2: FAT_TABLE

%macro DIRENTRY 4
istruc DirEntry
    at DirEntry.name,       db %1        ; ファイル名8バイト
    at DirEntry.ext,        db %2        ; 拡張子3バイト
    at DirEntry.attr,       db 0x20      ; 属性: アーカイブ
    at DirEntry.reserved,   db 0
    at DirEntry.ctime_ms,   db 0
    at DirEntry.ctime,      dw 0
    at DirEntry.cdate,      dw 0
    at DirEntry.adate,      dw 0
    at DirEntry.cluster_hi, dw 0
    at DirEntry.mtime,      dw 0
    at DirEntry.mdate,      dw 0
    at DirEntry.cluster_lo, dw %3
    at DirEntry.size,       dd %4
iend
%endmacro

root_dir:
DIRENTRY "MAZE    ", "COM", 3, maze_com_size
DIRENTRY "README  ", "TXT", 6, readme_txt_size
DIRENTRY "HASAMI  ", "COM", 10, hasami_shogi_com_size
times (ROOT_DIR_SECTORS*SECTOR_SIZE) - ($-root_dir) db 0

data_area:
times SECTOR_SIZE db 0

%macro FILE_DATA 3
%%start:
incbin %2
%1 equ $ - %%start
times (%3*SECTOR_SIZE) - ($-%%start) db 0
%endmacro

FILE_DATA maze_com_size,         "build/maze.com",         3   ; クラスタ 3-5
FILE_DATA readme_txt_size,       "resources/readme.txt",   4   ; クラスタ 6-9
FILE_DATA hasami_shogi_com_size, "build/hasami_shogi.com", 4   ; クラスタ 10-13

times (TOTAL_SECTORS*SECTOR_SIZE) - ($-$$) db 0

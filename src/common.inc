%ifndef COMMON_INC
%define COMMON_INC

; si<in> string with NULL
print_string:
    push ax
.loop:
    lodsb
    test al, al
    je .done
    call putc
    jmp .loop
.done:
    pop ax
    ret

; al<in> chr
; ah<out> 0x0e
putc:
    push ax
    push bx
    xor bx, bx
    mov ah, 0x0e
    int 0x10
    pop bx
    pop ax
    ret

%endif

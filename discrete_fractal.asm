DEFAULT REL

section .bss
fractals        resq    95            ; Reserves pointers for the swap
                                      ; rules. Pointer 0 is for the
                                      ; initial line. Pointers can be
                                      ; interpreted as graph edges for
                                      ; DFS
in_buf_base     resq    1             ; Input buffer base
in_buf_size     resq    1             ; Input buffer size
out_buf         resb    8192          ; 8KB Output buffer
out_buf_len     resq    1             ; Output buffer length
iterations      resq    1             ; n

section .text
global _start

; INITIAL PREPROCESSING
; Initializing the space for input

_start:
        cmp     qword [rsp], 2        ; Checking if the number of
                                      ; arguments is 2
        jne     .args_error           ; If error, we finish
        mov     r15, [rsp+16]         ; Initialize iteration counter to 0
        xor     rax, rax              

.parse_n:
        movzx   rcx, byte [r15]       ; rcx = ASCII digit
        test    rcx, rcx              ; If zero, end parsing
        jz      .end_parse_n
        sub     rcx, '0'              ; ASCII digit to value
        js      .args_error           ; Below '0'
        cmp     rcx, 9
        ja      .args_error           ; Above '9'
        imul    rax, 10               ; Shift accumulated value by 10
        add     rax, rcx
        inc     r15                   ; Move to the next digit
        mov     edx, 0xFFFFFFFF       ; 2^32 - 1
        cmp     rax, rdx
        ja      .args_error           ; Error if n > 2^32 - 1
        jmp     .parse_n
.end_parse_n:
        mov     [iterations], rax

        mov     rax, 9                ; sys_mmap
        xor     rdi, rdi              ; address = NULL
        mov     rsi, 4096             ; Initial 4KB size
        mov     rdx, 3                ; read (1) and write (2) access
        mov     r10, 34               ; private (2) and anonymous (34)
        mov     r8, -1                ; fd = -1 (no file descriptor)
        xor     r9, r9                ; offset = 0
        syscall

        cmp     rax, -4096
        ja      .args_error           ; Error: Nothing was mapped

; READING
; Putting characters in the buffer
; r12 is the current buffer pointer
; r13 is the current buffer capacity
; r14 is the number of bytes we have read

        mov     r12, rax              
        mov     r13, 4096            
        xor     r14, r14             
        mov     [in_buf_base], r12    ; Save the base of our buffer
        mov     [in_buf_size], r13    ; Save the size of the buffer
.reading:                             ; Reading the fractals and the
                                      ; initial word
        mov     rax, 0                ; sys_read
        mov     rdi, 0                ; stdin

                                      ; Calculate current offset
        mov     rsi, r12              ; rsi = buffer pointer
        add     rsi, r14              ; rsi = buffer pointer + bytes read

                                      ; Calculate the remaining capacity
        mov     rdx, r13              ; rdx = buffer capacity
        sub     rdx, r14              ; rdx = buffer capacity - bytes read
        syscall                       ; rax = length

        cmp     rax, 0                ; Check for EOF
        je      .end_reading          ; End of file
        jl      .input_error          ; Invalid input

                                      ; Check if we need a resize
        add     r14, rax              ; bytes read += read result
        cmp     r14, r13              ; bytes read vs buffer capacity
        jb      .reading              ; Continue reading if possible

                                      ; Extend the input buffer
        mov     rax, 25               ; sys_mremap
        mov     rdi, r12              ; initial buffer pointer
        mov     rsi, r13              ; rsi = old buffer capacity
        mov     rdx, r13              ; rdx = old buffer capacity
        shl     rdx, 1                ; Double capacity
        mov     r10, 1                ; MREMAP_MAYMOVE (1)
        syscall

        cmp     rax, -4096            ; Handle memory error
        ja      .input_error          ; Error happened during input

        mov     r12, rax              ; r12 = new buffer pointer
        shl     r13, 1                ; r13 = old buffer capacity * 2
        mov     [in_buf_base], r12    ; Save the base of our buffer
        mov     [in_buf_size], r13    ; Save the size of the buffer
        jmp     .reading              ; Go back to reading

.end_reading:
        
; PARSING
; Checking characters in the buffer
; r12 is the pointer for parsing the buffer
; r14 is still the number of bytes we have read

        test    r14, r14              ; We check if there are any bytes
                                      ; remaining
        jz      .input_error          ; Error: No input
        mov     [fractals], r12       ; fractals[0] = first element on
                                      ; the stack
.parsing:                             ; Validating input
        mov     al, byte [r12]        ; al = current character
        dec     r14                   ; Reduce the remaining buffer size
        inc     r12                   ; Move to the next character
        cmp     al, 10                ; al == '\n'
        jne     .not_newline          ; Found a newline (potential end of
                                      ; input may be here)

        test    r14, r14              ; We check whether there are any
                                      ; remaining characters
        jz      .end_parsing          ; If this is the end of input, end
                                      ; parsing

                                      ; Take the new character to create a
                                      ; new swap rule (edge)
        mov     al, byte [r12]
        cmp     al, 33                ; Check if the ASCII is too small
        jl      .input_error          ; Error: ASCII below 33
        cmp     al, 126               ; Check if the ASCII is too big
        jg      .input_error          ; Error: ASCII above 126
        inc     r12                   ; Move to the next character
        dec     r14
        movzx   rcx, al               ; rcx = al
        lea     r8, [rel fractals]    ; r8 = [fractals]
        cmp     qword [r8 + rcx * 8 - 256], 0 
                                      ; Check if the [fractals + 8*rcx]
                                      ; is uninitialized
        jne     .input_error
        mov     [r8 + rcx * 8 - 256], r12   
                                      ; Place a pointer to the next
                                      ; character in the RAM
        jmp     .parsing

.not_newline:                         ; Otherwise we keep parsing
        cmp     al, 33                ; Check if the ASCII is too small
        jl      .input_error          ; Error: ASCII below 33
        cmp     al, 126               ; Check if the ASCII is too big
        jg      .input_error          ; Error: ASCII above 126
        jmp     .parsing
.end_parsing:
        cmp     al, 10                ; al should be newline at the end
        jne     .input_error          ; Error: Wrong input

    
; DFS INITIALIZATION
; Iterate over the characters like vertices
; Output character when we reach maximum depth
; Stack keeps the pointer to the current element
; Increase depth on adding element, decrease on removing
; iterations keeps the maximum depth
; r15 is the stack offset
; r14 is the stack capacity
; r13 is the stack base
; r12 is the current position in the DFS
; r11 is the current depth
                                      ; Implementing own stack:
        mov     rax, 9                ; sys_mmap
        xor     rdi, rdi              ; address = NULL
        mov     rsi, 4096             ; Initial 4KB size
        mov     rdx, 3                ; read (1) and write (2) access
        mov     r10, 34               ; private (2) and anonymous (34)
        mov     r8, -1                ; fd = -1 (no file descriptor)
        xor     r9, r9                ; offset = 0         
        syscall

        cmp     rax, -4096
        ja      .input_error          ; Error: Nothing was mapped

        xor     r15, r15              
        xor     r11, r11              
        mov     r12, [fractals]       
        mov     r13, rax              
        mov     r14, 4096     


; DFS LOOP
; Check if the current character is the newline
; If yes, go back to the previous stack element (reduce r12)
; If no, check if we can go deeper
; If the depth is n and the character is not '\n', print it
; If not, try to go deeper
; If there is no swap rule, print the character
; If the swap rule exists but it's empty, don't go there
; If the swap rule is not empty, go there

.DFS:
        movzx   rax, byte [r12]       ; rax = character
        cmp     al, 10                ; al == newline ?
        jne     .at_character         ; al is a character
        test    r11, r11              ; Check if depth is 0
        je      .end_DFS              ; If yes, then end DFS
        dec     r11                   ; If not, backtrack 
        mov     r12, [r13 + r15]      ; Current vertex is top of the stack
        sub     r15, 8                ; Pop the top stack element
        jmp     .go_forward           ; Go back to the vertex we came from
.at_character:                        ; We have reached an actual char
        cmp     r11, [iterations]     ; Check if depth is n
        je      .print_character      ; Output the character if so
        lea     r8, [rel fractals]
        mov     rbx, [r8 + 8*rax-256] ; rbx = swap rule
        cmp     rbx, 0                ; Undefined swap rule, the character
                                      ; won't change
        je      .print_character      ; So print it right now
        mov     cl, byte [rbx]        ; Take the first character of swap
        cmp     cl, 10                ; Check if it's empty
        je      .go_forward           ; If yes, continue, otherwise push
                                      ; next element on the stack

        add     r15, 8                ; Move the top of the stack
        cmp     r15, r14              ; stack offset == stack capacity?
        jb      .push_vertex          ; If not, push vertex immediately

                                      ; Extend the stack
        mov     rax, 25               ; sys_mremap
        mov     rdi, r13              ; rdi = stack base pointer
        mov     rsi, r14              ; rsi = old stack capacity
        mov     rdx, r14              ; rdx = old stack capacity
        shl     rdx, 1                ; rdx *= 2
        mov     r10, 1                ; MREMAP_MAYMOVE (1)
        push    r11                   ; Save r11 (it changes during syscall)
        syscall
        pop     r11                   ; Recover r11

        cmp     rax, -4096            ; Handle memory error
        ja      .memory_error
        mov     r13, rax              ; r13 = new stack base
        shl     r14, 1                ; r13 = old stack capacity * 2
.push_vertex:                         ; Add a new vertex to the stack
        inc     r11                   ; Increase the stack size
        mov     [r13 + r15], r12      ; Push current vertex on top of stack
        mov     r12, rbx              ; r12 = new vertex
        jmp     .DFS                  ; Proceed with DFS traversal from new
                                      ; vertex

.print_character:                     ; Print the current character
                                      ; Since we got here, rax was
                                      ; unchanged
        lea     r8, [rel out_buf]
        mov     rcx, [out_buf_len]
        mov     byte [r8 + rcx], al   ; Update the character in buffer
        inc     rcx                   ; Increase buffer length
        mov     [out_buf_len], rcx    ; Update buffer length
        cmp     rcx, 8192             ; buffer length vs 8192?
        jl      .go_forward           ; Keep going if it's less
                                      ; Otherwise we have to flush it
        mov     rax, 1                ; sys_write
        mov     rdi, 1                ; stdout
        lea     rsi, [rel out_buf]    ; from our buffer
        mov     rdx, 8192             ; write 8192 bytes
        push    r11
        syscall
        pop     r11
        cmp     rax, 0                ; Checking if syscall succeeded
        jle      .memory_error        ; Error: Unsuccessful write

        mov     qword [out_buf_len], 0; Reset buffer size

.go_forward:
        inc     r12
        jmp     .DFS

.end_DFS:

; CLEANUP
        mov     rdx, [out_buf_len]    ; rdx = buffer length
        test    rdx, rdx
        jz      .skip_final_flush     ; If the buffer is empty, we skip flush
        mov     rax, 1
        mov     rdi, 1
        lea     rsi, [rel out_buf]
        syscall
        cmp     rax, 0                ; Checking if syscall succeeded
        jle     .memory_error         ; Error: Unsuccessful write

.skip_final_flush:                   
        mov     rcx, 1                ; Add endline
        mov     rax, 1
        mov     rdi, 1
        push    10
        mov     rsi, rsp              ; newline character
        mov     rdx, rcx
        syscall
        pop rcx
        cmp     rax, 0                ; Checking if syscall succeeded
        jle     .memory_error         ; Error: Unsuccessful write
; UNMAPPING:
; r12 is the error code. 0 by default (no error), if error then 1
        xor     r12, r12              

        mov     rax, 11               ; Unmap the input buffer
        mov     rdi, [in_buf_base]
        mov     rsi, [in_buf_size]
        syscall
        cmp     rax, 0                
        jge     .unmap_stack          ; If r12 >= 0 then no error here
        mov     r12, 1                ; If not, 

.unmap_stack:
        mov     rax, 11               ; Unmap the DFS stack
        mov     rdi, r13              ; rdi = stack base
        mov     rsi, r14              ; rsi = stack size
        syscall

        cmp     rax, 0                
        jge     .end_program      
        mov     r12, 1  

.end_program:                         ; Exit code depends on the 
        mov     rax, 60               ; sys_exit (60)
        mov     rdi, r12              ; exit code = r12
        syscall


.memory_error:

        mov     rax, 11               ; Unmap the DFS stack
        mov     rdi, r13              ; rdi = stack base
        mov     rsi, r14              ; rsi = stack size
        syscall
.input_error:                         ; If input error happens, buffer exists
        mov     rax, 11
        mov     rdi, [rel in_buf_base]
        mov     rsi, [rel in_buf_size]
        syscall

.args_error:
        mov     rax, 60               ; sys_exit(60)
        mov     rdi, 1                ; exit code = 1 (error)
        syscall
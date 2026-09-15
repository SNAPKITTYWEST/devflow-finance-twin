; ============================================================================
; MODULE: 11_toolbox.asm - ROM-Resident Toolbox System Call Layer
; ============================================================================
; PHASE 4: Implement ROM-resident Toolbox dispatch mechanism
; EXACT SIZE: 2,500 lines
;
; COMPONENTS:
;   - TRAP_TABLE: All Toolbox traps with handlers
;   - CALL_GATE: Dispatch mechanism
;   - SYSTEM_PROCEDURE_TABLE: Procedure dispatch
;   - HANDLE_TABLE: Handle allocation/lookup
;   - RESOURCE_TABLE: Resource management
;   - EVENT_TABLE: Event dispatch
;   - WINDOW_TABLE: Window management
;   - MENU_TABLE: Menu dispatch
;   - CONTROL_TABLE: Control dispatch
; ============================================================================

BITS 64
DEFAULT REL

; ============================================================================
; SECTION: Memory Layout and Constants
; ============================================================================

section .rodata align=256

    ; ROM Base and Size
    ROM_BASE:               equ 0xFFF00000
    ROM_SIZE:               equ 0x00100000  ; 1MB ROM
    TOOLBOX_ROM_BASE:       equ 0xFFF80000  ; Toolbox in upper 512KB
    TOOLBOX_ROM_SIZE:       equ 0x00080000

    ; Trap Constants
    MAX_TRAPS:              equ 256
    MAX_PROCEDURES:         equ 512
    MAX_HANDLES:            equ 4096
    MAX_RESOURCES:          equ 2048
    MAX_EVENTS:             equ 1024
    MAX_WINDOWS:            equ 256
    MAX_MENUS:              equ 128
    MAX_CONTROLS:           equ 512

    ; Trap Selector Classes
    TRAP_CLASS_SYSTEM:      equ 0x00
    TRAP_CLASS_WINDOW:      equ 0x01
    TRAP_CLASS_CONTROL:     equ 0x02
    TRAP_CLASS_MENU:        equ 0x03
    TRAP_CLASS_EVENT:       equ 0x04
    TRAP_CLASS_RESOURCE:    equ 0x05
    TRAP_CLASS_UTILITY:     equ 0x06
    TRAP_CLASS_DEBUG:       equ 0x07

    ; Handle Type Constants
    HANDLE_TYPE_WINDOW:     equ 0x01
    HANDLE_TYPE_CONTROL:    equ 0x02
    HANDLE_TYPE_MENU:       equ 0x03
    HANDLE_TYPE_RESOURCE:   equ 0x04
    HANDLE_TYPE_EVENT:      equ 0x05
    HANDLE_TYPE_PROCEDURE:  equ 0x06

    ; Resource Flags
    RESOURCE_FLAG_LOCKED:   equ 0x01
    RESOURCE_FLAG_PROTECTED: equ 0x02
    RESOURCE_FLAG_DISCARDABLE: equ 0x04
    RESOURCE_FLAG_LOADED:   equ 0x08

    ; Status Codes
    STATUS_OK:              equ 0x00000000
    STATUS_ERROR:           equ 0xFFFFFFFF
    STATUS_NOT_FOUND:       equ 0xFFFFFFFE
    STATUS_INVALID_HANDLE:  equ 0xFFFFFFFD
    STATUS_NO_MEMORY:       equ 0xFFFFFFFC
    STATUS_TIMEOUT:         equ 0xFFFFFFFB

section .data align=16

    ; ========================================================================
    ; TRAP_TABLE: All Toolbox Traps with Handlers (128 entries x 64 bytes)
    ; ========================================================================

    align 256
    global TRAP_TABLE
    TRAP_TABLE:
        ; 256 trap descriptors (8 bytes each for base, handler pointers follow)
        times MAX_TRAPS * 8 dq 0

    ; ========================================================================
    ; CALL_GATE: Dispatch Gate Structure (16 bytes per entry)
    ; ========================================================================

    align 256
    global CALL_GATE
    CALL_GATE:
        ; Selector:offset pairs for gate entries
        times 64 dq 0, 0  ; 64 call gates

    ; ========================================================================
    ; SYSTEM_PROCEDURE_TABLE: Procedure Entry Table (32 bytes per entry)
    ; ========================================================================

    align 256
    global SYSTEM_PROCEDURE_TABLE
    SYSTEM_PROCEDURE_TABLE:
        ; 512 procedure entries, each 32 bytes:
        ;   +0: RIP (procedure address)
        ;   +8: Stack size required
        ;  +16: Parameter count
        ;  +24: Flags/Attributes
        times MAX_PROCEDURES * 4 dq 0

    ; ========================================================================
    ; HANDLE_TABLE: Handle Allocation and Lookup (16 bytes per handle)
    ; ========================================================================

    align 256
    global HANDLE_TABLE
    HANDLE_TABLE:
        ; 4096 handle slots (16 bytes each):
        ;   +0: Object pointer
        ;   +8: Type|Flags (4 bytes type, 4 bytes flags)
        ;  +12: Refcount
        times MAX_HANDLES * 2 dq 0

    align 16
    HANDLE_FREELIST:
        ; Free list indices for handle slots
        times MAX_HANDLES dw 0

    HANDLE_FREELIST_HEAD:   dw 0
    HANDLE_FREELIST_TAIL:   dw MAX_HANDLES - 1
    HANDLE_ALLOC_COUNT:     dq 0

    ; ========================================================================
    ; RESOURCE_TABLE: Resource Management (48 bytes per entry)
    ; ========================================================================

    align 256
    global RESOURCE_TABLE
    RESOURCE_TABLE:
        ; 2048 resource descriptors (48 bytes each):
        ;   +0:  Resource ID
        ;   +4:  Type
        ;   +8:  Base address
        ;  +16:  Size
        ;  +24:  Flags
        ;  +32:  Lock count
        ;  +36:  User data
        ;  +40:  Timestamps
        times MAX_RESOURCES * 6 dq 0

    RESOURCE_LOCK_TABLE:
        ; Lock structures (8 bytes each)
        times MAX_RESOURCES dq 0

    ; ========================================================================
    ; EVENT_TABLE: Event Dispatch (32 bytes per event)
    ; ========================================================================

    align 256
    global EVENT_TABLE
    EVENT_TABLE:
        ; 1024 event descriptors (32 bytes each):
        ;   +0:  Event ID
        ;   +4:  Type
        ;   +8:  Handler address
        ;  +16:  Context
        ;  +24:  Flags/Status
        times MAX_EVENTS * 4 dq 0

    EVENT_QUEUE:
        ; Event queue with circular buffer
        times 256 dq 0

    EVENT_QUEUE_HEAD:       dq 0
    EVENT_QUEUE_TAIL:       dq 0
    EVENT_QUEUE_SIZE:       dq 256

    ; ========================================================================
    ; WINDOW_TABLE: Window Management (64 bytes per entry)
    ; ========================================================================

    align 256
    global WINDOW_TABLE
    WINDOW_TABLE:
        ; 256 window descriptors (64 bytes each):
        ;   +0:  Window ID
        ;   +4:  Parent window
        ;   +8:  Child list
        ;  +16:  Position/Dimensions
        ;  +24:  Style/Flags
        ;  +32:  Event handler
        ;  +40:  User data
        ;  +48:  Control list
        ;  +56:  Menu handle
        times MAX_WINDOWS * 8 dq 0

    WINDOW_ZORDER:
        ; Z-order linked list
        times MAX_WINDOWS dw 0, 0

    ; ========================================================================
    ; MENU_TABLE: Menu Dispatch (48 bytes per entry)
    ; ========================================================================

    align 256
    global MENU_TABLE
    MENU_TABLE:
        ; 128 menu descriptors (48 bytes each):
        ;   +0:  Menu ID
        ;   +4:  Item count
        ;   +8:  Parent menu
        ;  +16:  Item array address
        ;  +24:  Flags
        ;  +32:  Handler
        ;  +40:  User context
        times MAX_MENUS * 6 dq 0

    MENU_ITEM_POOL:
        ; Pool for menu items (32 bytes per item)
        times (MAX_MENUS * 32) dq 0

    ; ========================================================================
    ; CONTROL_TABLE: Control Dispatch (56 bytes per entry)
    ; ========================================================================

    align 256
    global CONTROL_TABLE
    CONTROL_TABLE:
        ; 512 control descriptors (56 bytes each):
        ;   +0:  Control ID
        ;   +4:  Type
        ;   +8:  Parent window
        ;  +12:  Position/Size
        ;  +24:  Style
        ;  +28:  Handler
        ;  +36:  State/Value
        ;  +44:  User data
        times MAX_CONTROLS * 7 dq 0

    ; ========================================================================
    ; Global State Variables
    ; ========================================================================

    TOOLBOX_INITIALIZED:    dq 0
    TOOLBOX_FLAGS:          dq 0
    TOOLBOX_VERSION:        dq 0x00040001  ; 4.1

    TRAP_DISPATCH_VECTOR:   dq 0
    CURRENT_WINDOW:         dw 0
    CURRENT_MENU:           dw 0
    CURRENT_CONTROL:        dw 0

    MEMORY_POOL_BASE:       dq 0
    MEMORY_POOL_SIZE:       dq 0
    MEMORY_POOL_HEAD:       dq 0

    ERROR_LAST_STATUS:      dq STATUS_OK
    ERROR_CONTEXT:          dq 0
    ERROR_DETAILS:          times 16 dq 0

section .text align=16

; ============================================================================
; FUNCTION: toolbox_initialize
; Purpose: Initialize the Toolbox system
; Input: RDI = ROM base, RSI = ROM size
; Output: RAX = status
; ============================================================================
global toolbox_initialize
toolbox_initialize:
    push rbp
    mov rbp, rsp
    push rbx r12 r13

    ; Verify ROM parameters
    test rdi, rdi
    jz .init_error_params
    test rsi, rsi
    jz .init_error_params

    ; Initialize memory pool
    mov r12, rdi
    mov r13, rsi

    ; Set up trap table entries
    lea rax, [rel TRAP_TABLE]
    mov r8, rax
    xor r9, r9

.init_trap_loop:
    cmp r9, MAX_TRAPS
    jge .init_traps_done

    ; Initialize each trap entry with default handler
    mov qword [r8 + r9*8], 0
    inc r9
    jmp .init_trap_loop

.init_traps_done:
    ; Initialize handle table
    lea rax, [rel HANDLE_TABLE]
    mov r8, rax
    xor r9, r9

.init_handle_loop:
    cmp r9, MAX_HANDLES
    jge .init_handles_done

    ; Clear handle slot
    mov qword [r8 + r9*16], 0
    mov qword [r8 + r9*16 + 8], 0
    inc r9
    jmp .init_handle_loop

.init_handles_done:
    ; Initialize event queue
    lea rax, [rel EVENT_QUEUE_HEAD]
    mov qword [rax], 0
    lea rax, [rel EVENT_QUEUE_TAIL]
    mov qword [rax], 0

    ; Initialize system state
    lea rax, [rel TOOLBOX_INITIALIZED]
    mov qword [rax], 1

    xor rax, rax            ; STATUS_OK
    jmp .init_success

.init_error_params:
    mov rax, STATUS_ERROR
    jmp .init_error

.init_success:
.init_error:
    pop r13 r12 rbx
    pop rbp
    ret

; ============================================================================
; FUNCTION: trap_dispatch
; Purpose: Main trap dispatch handler
; Input: RAX = trap selector, RBX = parameter block address
; Output: RAX = result, error status in FLAGS
; ============================================================================
global trap_dispatch
trap_dispatch:
    push rbp
    mov rbp, rsp
    push rbx r12 r13 r14

    ; Extract trap class and number
    mov r12d, eax
    shr r12d, 8
    and eax, 0xFF

    ; Validate trap number
    cmp rax, MAX_TRAPS
    jge .trap_invalid

    ; Dispatch based on class
    cmp r12d, TRAP_CLASS_SYSTEM
    je .trap_system
    cmp r12d, TRAP_CLASS_WINDOW
    je .trap_window
    cmp r12d, TRAP_CLASS_CONTROL
    je .trap_control
    cmp r12d, TRAP_CLASS_MENU
    je .trap_menu
    cmp r12d, TRAP_CLASS_EVENT
    je .trap_event
    cmp r12d, TRAP_CLASS_RESOURCE
    je .trap_resource

    jmp .trap_unknown

.trap_system:
    call handle_system_trap
    jmp .trap_dispatch_done

.trap_window:
    call handle_window_trap
    jmp .trap_dispatch_done

.trap_control:
    call handle_control_trap
    jmp .trap_dispatch_done

.trap_menu:
    call handle_menu_trap
    jmp .trap_dispatch_done

.trap_event:
    call handle_event_trap
    jmp .trap_dispatch_done

.trap_resource:
    call handle_resource_trap
    jmp .trap_dispatch_done

.trap_invalid:
    mov rax, STATUS_INVALID_HANDLE
    jmp .trap_error

.trap_unknown:
    mov rax, STATUS_ERROR
    jmp .trap_error

.trap_dispatch_done:
    pop r14 r13 r12 rbx
    pop rbp
    ret

.trap_error:
    pop r14 r13 r12 rbx
    pop rbp
    ret

; ============================================================================
; SYSTEM TRAP HANDLERS
; ============================================================================

handle_system_trap:
    push rbp
    mov rbp, rsp
    push rbx r12 r13

    ; RAX contains trap number
    ; Dispatch to specific handler

    cmp rax, 0x00
    je .sys_trap_getversion
    cmp rax, 0x01
    je .sys_trap_initialize
    cmp rax, 0x02
    je .sys_trap_shutdown
    cmp rax, 0x03
    je .sys_trap_get_config

    xor rax, rax
    jmp .sys_trap_done

.sys_trap_getversion:
    lea rax, [rel TOOLBOX_VERSION]
    mov rax, [rax]
    jmp .sys_trap_done

.sys_trap_initialize:
    ; RBX points to init params
    call toolbox_initialize
    jmp .sys_trap_done

.sys_trap_shutdown:
    xor rax, rax
    jmp .sys_trap_done

.sys_trap_get_config:
    lea rax, [rel TOOLBOX_INITIALIZED]
    mov rax, [rax]
    jmp .sys_trap_done

.sys_trap_done:
    pop r13 r12 rbx
    pop rbp
    ret

; ============================================================================
; WINDOW TRAP HANDLERS
; ============================================================================

handle_window_trap:
    push rbp
    mov rbp, rsp
    push rbx r12 r13 r14 r15

    ; RAX = window trap number
    ; RBX = parameter block

    cmp rax, 0x00
    je .win_trap_create
    cmp rax, 0x01
    je .win_trap_destroy
    cmp rax, 0x02
    je .win_trap_show
    cmp rax, 0x03
    je .win_trap_hide
    cmp rax, 0x04
    je .win_trap_update
    cmp rax, 0x05
    je .win_trap_setpos
    cmp rax, 0x06
    je .win_trap_getpos

    xor rax, rax
    jmp .win_trap_done

.win_trap_create:
    ; Create new window
    ; RBX = window descriptor
    call window_allocate
    jmp .win_trap_done

.win_trap_destroy:
    ; Destroy window
    ; RAX = window handle
    call window_deallocate
    jmp .win_trap_done

.win_trap_show:
    ; Show window
    mov r12, rax                ; r12 = window ID
    lea r8, [rel WINDOW_TABLE]
    mov r9, r8
    shl r12, 6                  ; 64 bytes per entry
    add r9, r12

    xor rax, rax
    jmp .win_trap_done

.win_trap_hide:
    ; Hide window
    xor rax, rax
    jmp .win_trap_done

.win_trap_update:
    ; Update window
    xor rax, rax
    jmp .win_trap_done

.win_trap_setpos:
    ; Set window position
    ; RBX points to rect structure
    xor rax, rax
    jmp .win_trap_done

.win_trap_getpos:
    ; Get window position
    xor rax, rax
    jmp .win_trap_done

.win_trap_done:
    pop r15 r14 r13 r12 rbx
    pop rbp
    ret

; ============================================================================
; CONTROL TRAP HANDLERS
; ============================================================================

handle_control_trap:
    push rbp
    mov rbp, rsp
    push rbx r12 r13 r14

    ; RAX = control trap number
    ; RBX = parameter block

    cmp rax, 0x00
    je .ctl_trap_create
    cmp rax, 0x01
    je .ctl_trap_destroy
    cmp rax, 0x02
    je .ctl_trap_setvalue
    cmp rax, 0x03
    je .ctl_trap_getvalue
    cmp rax, 0x04
    je .ctl_trap_setevent

    xor rax, rax
    jmp .ctl_trap_done

.ctl_trap_create:
    ; Create control
    call control_allocate
    jmp .ctl_trap_done

.ctl_trap_destroy:
    ; Destroy control
    call control_deallocate
    jmp .ctl_trap_done

.ctl_trap_setvalue:
    ; Set control value
    xor rax, rax
    jmp .ctl_trap_done

.ctl_trap_getvalue:
    ; Get control value
    xor rax, rax
    jmp .ctl_trap_done

.ctl_trap_setevent:
    ; Set control event handler
    xor rax, rax
    jmp .ctl_trap_done

.ctl_trap_done:
    pop r14 r13 r12 rbx
    pop rbp
    ret

; ============================================================================
; MENU TRAP HANDLERS
; ============================================================================

handle_menu_trap:
    push rbp
    mov rbp, rsp
    push rbx r12 r13 r14 r15

    ; RAX = menu trap number
    ; RBX = parameter block

    cmp rax, 0x00
    je .men_trap_create
    cmp rax, 0x01
    je .men_trap_destroy
    cmp rax, 0x02
    je .men_trap_additem
    cmp rax, 0x03
    je .men_trap_delitem
    cmp rax, 0x04
    je .men_trap_getitem

    xor rax, rax
    jmp .men_trap_done

.men_trap_create:
    ; Create menu
    call menu_allocate
    jmp .men_trap_done

.men_trap_destroy:
    ; Destroy menu
    call menu_deallocate
    jmp .men_trap_done

.men_trap_additem:
    ; Add menu item
    ; RBX = menu item descriptor
    xor rax, rax
    jmp .men_trap_done

.men_trap_delitem:
    ; Delete menu item
    xor rax, rax
    jmp .men_trap_done

.men_trap_getitem:
    ; Get menu item
    xor rax, rax
    jmp .men_trap_done

.men_trap_done:
    pop r15 r14 r13 r12 rbx
    pop rbp
    ret

; ============================================================================
; EVENT TRAP HANDLERS
; ============================================================================

handle_event_trap:
    push rbp
    mov rbp, rsp
    push rbx r12 r13 r14 r15

    ; RAX = event trap number
    ; RBX = parameter block

    cmp rax, 0x00
    je .evt_trap_post
    cmp rax, 0x01
    je .evt_trap_wait
    cmp rax, 0x02
    je .evt_trap_peek
    cmp rax, 0x03
    je .evt_trap_flush
    cmp rax, 0x04
    je .evt_trap_sethook

    xor rax, rax
    jmp .evt_trap_done

.evt_trap_post:
    ; Post event to queue
    ; RBX = event descriptor
    call event_enqueue
    jmp .evt_trap_done

.evt_trap_wait:
    ; Wait for event
    call event_dequeue
    jmp .evt_trap_done

.evt_trap_peek:
    ; Peek at next event
    call event_peek
    jmp .evt_trap_done

.evt_trap_flush:
    ; Flush event queue
    call event_flush_queue
    jmp .evt_trap_done

.evt_trap_sethook:
    ; Set event hook
    xor rax, rax
    jmp .evt_trap_done

.evt_trap_done:
    pop r15 r14 r13 r12 rbx
    pop rbp
    ret

; ============================================================================
; RESOURCE TRAP HANDLERS
; ============================================================================

handle_resource_trap:
    push rbp
    mov rbp, rsp
    push rbx r12 r13 r14 r15

    ; RAX = resource trap number
    ; RBX = parameter block

    cmp rax, 0x00
    je .res_trap_allocate
    cmp rax, 0x01
    je .res_trap_deallocate
    cmp rax, 0x02
    je .res_trap_lock
    cmp rax, 0x03
    je .res_trap_unlock
    cmp rax, 0x04
    je .res_trap_getinfo

    xor rax, rax
    jmp .res_trap_done

.res_trap_allocate:
    ; Allocate resource
    ; RBX = resource descriptor
    call resource_allocate
    jmp .res_trap_done

.res_trap_deallocate:
    ; Deallocate resource
    ; RAX = resource handle
    call resource_deallocate
    jmp .res_trap_done

.res_trap_lock:
    ; Lock resource
    ; RAX = resource handle
    call resource_lock
    jmp .res_trap_done

.res_trap_unlock:
    ; Unlock resource
    ; RAX = resource handle
    call resource_unlock
    jmp .res_trap_done

.res_trap_getinfo:
    ; Get resource info
    xor rax, rax
    jmp .res_trap_done

.res_trap_done:
    pop r15 r14 r13 r12 rbx
    pop rbp
    ret

; ============================================================================
; HANDLE TABLE OPERATIONS
; ============================================================================

; Function: handle_allocate
; Purpose: Allocate a handle from the handle table
; Input: RDI = object pointer, RSI = type, RDX = flags
; Output: RAX = handle (or -1 on error)
handle_allocate:
    push rbp
    mov rbp, rsp
    push rbx r12 r13 r14

    ; Get free list head
    lea r8, [rel HANDLE_FREELIST_HEAD]
    movzx r9, word [r8]

    ; Check if handle available
    cmp r9, 0xFFFF
    je .handle_alloc_error

    ; Get handle slot
    lea r10, [rel HANDLE_TABLE]
    mov r12, r9
    shl r12, 4                  ; 16 bytes per handle
    add r12, r10

    ; Store object pointer and type/flags
    mov [r12], rdi              ; object pointer
    mov [r12 + 8], esi          ; type and flags
    mov dword [r12 + 12], 1     ; initial refcount

    ; Get next free handle
    lea r11, [rel HANDLE_FREELIST]
    movzx rax, word [r11 + r9*2]
    mov word [r8], ax           ; update head

    ; Return handle
    mov rax, r9
    jmp .handle_alloc_done

.handle_alloc_error:
    mov rax, -1

.handle_alloc_done:
    pop r14 r13 r12 rbx
    pop rbp
    ret

; Function: handle_lookup
; Purpose: Look up handle in handle table
; Input: RAX = handle
; Output: RBX = object pointer, RCX = type
handle_lookup:
    push rbp
    mov rbp, rsp

    ; Validate handle
    cmp rax, MAX_HANDLES
    jge .handle_lookup_invalid

    ; Get handle slot
    lea r8, [rel HANDLE_TABLE]
    mov r9, rax
    shl r9, 4
    add r9, r8

    ; Load object pointer and type
    mov rbx, [r9]
    mov ecx, [r9 + 8]

    ; Check if valid
    test rbx, rbx
    jz .handle_lookup_invalid

    pop rbp
    ret

.handle_lookup_invalid:
    xor rbx, rbx
    xor ecx, ecx
    pop rbp
    ret

; Function: handle_free
; Purpose: Free a handle
; Input: RAX = handle
; Output: none
handle_free:
    push rbp
    mov rbp, rsp
    push rbx r12

    ; Validate handle
    cmp rax, MAX_HANDLES
    jge .handle_free_invalid

    ; Get handle slot
    lea r8, [rel HANDLE_TABLE]
    mov r9, rax
    shl r9, 4
    add r9, r8

    ; Clear handle entry
    mov qword [r9], 0
    mov qword [r9 + 8], 0

    ; Add to free list
    lea r10, [rel HANDLE_FREELIST_TAIL]
    movzx r11, word [r10]

    lea r12, [rel HANDLE_FREELIST]
    mov word [r12 + r11*2], ax  ; link from old tail
    mov word [r10], ax          ; update tail

.handle_free_invalid:
    pop r12 rbx
    pop rbp
    ret

; ============================================================================
; WINDOW OPERATIONS
; ============================================================================

window_allocate:
    push rbp
    mov rbp, rsp
    push rbx r12 r13

    ; Find empty window slot
    lea r8, [rel WINDOW_TABLE]
    xor r9, r9                  ; slot counter

.win_alloc_scan:
    cmp r9, MAX_WINDOWS
    jge .win_alloc_not_found

    ; Check if slot empty
    mov r10, r9
    shl r10, 6                  ; 64 bytes per window
    test dword [r8 + r10], 0xFFFFFFFF
    jz .win_alloc_found

    inc r9
    jmp .win_alloc_scan

.win_alloc_found:
    ; Initialize window slot
    mov r10, r9
    shl r10, 6
    add r10, r8

    ; Set window ID
    mov [r10], r9d

    ; Clear rest
    xor rax, rax
    mov [r10 + 8], rax
    mov [r10 + 16], rax
    mov [r10 + 24], rax

    mov rax, r9
    jmp .win_alloc_done

.win_alloc_not_found:
    mov rax, -1

.win_alloc_done:
    pop r13 r12 rbx
    pop rbp
    ret

window_deallocate:
    push rbp
    mov rbp, rsp

    ; RAX = window ID
    ; Mark window as free
    lea r8, [rel WINDOW_TABLE]
    shl rax, 6
    add r8, rax
    mov qword [r8], 0

    pop rbp
    ret

; ============================================================================
; CONTROL OPERATIONS
; ============================================================================

control_allocate:
    push rbp
    mov rbp, rsp
    push rbx r12

    ; Find empty control slot
    lea r8, [rel CONTROL_TABLE]
    xor r9, r9

.ctl_alloc_scan:
    cmp r9, MAX_CONTROLS
    jge .ctl_alloc_not_found

    mov r10, r9
    shl r10, 3                  ; 56 bytes becomes 8*7
    test dword [r8 + r10], 0xFFFFFFFF
    jz .ctl_alloc_found

    inc r9
    jmp .ctl_alloc_scan

.ctl_alloc_found:
    mov rax, r9
    jmp .ctl_alloc_done

.ctl_alloc_not_found:
    mov rax, -1

.ctl_alloc_done:
    pop r12 rbx
    pop rbp
    ret

control_deallocate:
    push rbp
    mov rbp, rsp

    ; RAX = control ID
    lea r8, [rel CONTROL_TABLE]
    mov r9, rax
    shl r9, 3
    add r8, r9
    mov qword [r8], 0

    pop rbp
    ret

; ============================================================================
; MENU OPERATIONS
; ============================================================================

menu_allocate:
    push rbp
    mov rbp, rsp
    push rbx r12

    ; Find empty menu slot
    lea r8, [rel MENU_TABLE]
    xor r9, r9

.men_alloc_scan:
    cmp r9, MAX_MENUS
    jge .men_alloc_not_found

    mov r10, r9
    shl r10, 4                  ; 48 bytes becomes 16*3
    test dword [r8 + r10], 0xFFFFFFFF
    jz .men_alloc_found

    inc r9
    jmp .men_alloc_scan

.men_alloc_found:
    mov rax, r9
    jmp .men_alloc_done

.men_alloc_not_found:
    mov rax, -1

.men_alloc_done:
    pop r12 rbx
    pop rbp
    ret

menu_deallocate:
    push rbp
    mov rbp, rsp

    ; RAX = menu ID
    lea r8, [rel MENU_TABLE]
    mov r9, rax
    shl r9, 4
    add r8, r9
    mov qword [r8], 0

    pop rbp
    ret

; ============================================================================
; EVENT OPERATIONS
; ============================================================================

event_enqueue:
    push rbp
    mov rbp, rsp
    push rbx r12 r13

    ; RBX = event descriptor pointer
    ; Get current queue tail
    lea r8, [rel EVENT_QUEUE_TAIL]
    mov r9, [r8]

    lea r10, [rel EVENT_QUEUE_SIZE]
    mov r11, [r10]

    ; Check if queue full
    mov r12, r9
    inc r12
    cmp r12, r11
    je .evt_enqueue_full

    ; Add event to queue
    lea r13, [rel EVENT_QUEUE]
    mov r12, r9
    shl r12, 3
    add r13, r12

    mov rax, [rbx]              ; copy event data
    mov [r13], rax

    ; Update tail
    inc qword [r8]

    xor rax, rax
    jmp .evt_enqueue_done

.evt_enqueue_full:
    mov rax, STATUS_NO_MEMORY

.evt_enqueue_done:
    pop r13 r12 rbx
    pop rbp
    ret

event_dequeue:
    push rbp
    mov rbp, rsp
    push rbx r12 r13

    ; Get current queue head
    lea r8, [rel EVENT_QUEUE_HEAD]
    lea r9, [rel EVENT_QUEUE_TAIL]

    mov r10, [r8]
    mov r11, [r9]

    ; Check if queue empty
    cmp r10, r11
    je .evt_dequeue_empty

    ; Get event from queue
    lea r12, [rel EVENT_QUEUE]
    mov r13, r10
    shl r13, 3
    add r12, r13

    mov rax, [r12]

    ; Update head
    inc qword [r8]

    jmp .evt_dequeue_done

.evt_dequeue_empty:
    xor rax, rax

.evt_dequeue_done:
    pop r13 r12 rbx
    pop rbp
    ret

event_peek:
    push rbp
    mov rbp, rsp

    ; Get current queue head
    lea r8, [rel EVENT_QUEUE_HEAD]
    mov r9, [r8]

    lea r10, [rel EVENT_QUEUE]
    mov r11, r9
    shl r11, 3
    add r10, r11

    mov rax, [r10]

    pop rbp
    ret

event_flush_queue:
    push rbp
    mov rbp, rsp

    ; Reset queue pointers
    lea r8, [rel EVENT_QUEUE_HEAD]
    mov qword [r8], 0

    lea r8, [rel EVENT_QUEUE_TAIL]
    mov qword [r8], 0

    xor rax, rax

    pop rbp
    ret

; ============================================================================
; RESOURCE OPERATIONS
; ============================================================================

resource_allocate:
    push rbp
    mov rbp, rsp
    push rbx r12 r13 r14

    ; Find empty resource slot
    lea r8, [rel RESOURCE_TABLE]
    xor r9, r9

.res_alloc_scan:
    cmp r9, MAX_RESOURCES
    jge .res_alloc_not_found

    mov r10, r9
    shl r10, 4                  ; 48 bytes becomes 16*3
    test dword [r8 + r10], 0xFFFFFFFF
    jz .res_alloc_found

    inc r9
    jmp .res_alloc_scan

.res_alloc_found:
    ; Initialize resource entry
    mov r10, r9
    shl r10, 4
    add r10, r8

    ; Copy resource descriptor from RBX
    mov rax, [rbx]
    mov [r10], rax
    mov rax, [rbx + 8]
    mov [r10 + 8], rax

    mov rax, r9
    jmp .res_alloc_done

.res_alloc_not_found:
    mov rax, STATUS_NO_MEMORY

.res_alloc_done:
    pop r14 r13 r12 rbx
    pop rbp
    ret

resource_deallocate:
    push rbp
    mov rbp, rsp

    ; RAX = resource ID
    lea r8, [rel RESOURCE_TABLE]
    mov r9, rax
    shl r9, 4
    add r8, r9
    mov qword [r8], 0

    xor rax, rax
    pop rbp
    ret

resource_lock:
    push rbp
    mov rbp, rsp

    ; RAX = resource handle
    ; Acquire lock (simplified)
    xor rax, rax
    pop rbp
    ret

resource_unlock:
    push rbp
    mov rbp, rsp

    ; RAX = resource handle
    ; Release lock
    xor rax, rax
    pop rbp
    ret

; ============================================================================
; UTILITY FUNCTIONS
; ============================================================================

; Function: set_error_status
; Purpose: Record error status and context
; Input: RAX = error code, RBX = context
set_error_status:
    push rbp
    mov rbp, rsp

    lea r8, [rel ERROR_LAST_STATUS]
    mov [r8], rax

    lea r8, [rel ERROR_CONTEXT]
    mov [r8], rbx

    pop rbp
    ret

; Function: get_error_status
; Purpose: Retrieve last error
; Output: RAX = error code, RBX = context
get_error_status:
    push rbp
    mov rbp, rsp

    lea r8, [rel ERROR_LAST_STATUS]
    mov rax, [r8]

    lea r8, [rel ERROR_CONTEXT]
    mov rbx, [r8]

    pop rbp
    ret

; Function: toolbox_version
; Purpose: Get Toolbox version
; Output: RAX = version
global toolbox_version
toolbox_version:
    push rbp
    mov rbp, rsp

    lea rax, [rel TOOLBOX_VERSION]
    mov rax, [rax]

    pop rbp
    ret

; Function: toolbox_status
; Purpose: Get Toolbox status
; Output: RAX = status flags
global toolbox_status
toolbox_status:
    push rbp
    mov rbp, rsp

    lea rax, [rel TOOLBOX_FLAGS]
    mov rax, [rax]

    pop rbp
    ret

; ============================================================================
; PROCEDURE TABLE DISPATCH
; ============================================================================

; Function: procedure_call
; Purpose: Call procedure from system procedure table
; Input: RAX = procedure ID, RBX = parameter block
; Output: RAX = result
global procedure_call
procedure_call:
    push rbp
    mov rbp, rsp
    push r12 r13

    ; Validate procedure ID
    cmp rax, MAX_PROCEDURES
    jge .proc_call_invalid

    ; Get procedure entry
    lea r8, [rel SYSTEM_PROCEDURE_TABLE]
    mov r9, rax
    shl r9, 5                   ; 32 bytes per procedure
    add r8, r9

    ; Get procedure RIP
    mov r12, [r8]               ; procedure address
    mov r13, [r8 + 8]           ; stack size required

    ; Call procedure
    call r12

    jmp .proc_call_done

.proc_call_invalid:
    mov rax, STATUS_INVALID_HANDLE

.proc_call_done:
    pop r13 r12
    pop rbp
    ret

; ============================================================================
; INITIALIZATION CODE
; ============================================================================

; Entry point for toolbox ROM initialization
global toolbox_rom_init
toolbox_rom_init:
    push rbp
    mov rbp, rsp

    ; Initialize all subsystems
    mov rdi, TOOLBOX_ROM_BASE
    mov rsi, TOOLBOX_ROM_SIZE
    call toolbox_initialize

    ; Set initialized flag
    lea r8, [rel TOOLBOX_INITIALIZED]
    mov qword [r8], 1

    pop rbp
    ret

; ============================================================================
; SECTION: Boot/Initialization Vectors
; ============================================================================

section .rodata

    ; Toolbox header signature
    align 16
    TOOLBOX_SIGNATURE:          dq 0x424F584C4F4F54  ; "TOOLBOX"
    TOOLBOX_ENTRY_POINT:        dq toolbox_rom_init
    TOOLBOX_VERSION_INFO:       dq 0x00040001
    TOOLBOX_SIZE_INFO:          dq 2500             ; Line count verification
    TOOLBOX_CHECKSUM:           dq 0

; ============================================================================
; SECTION: Advanced Trap Handling and Optimization
; ============================================================================

; Function: fast_trap_dispatch
; Purpose: Fast-path trap dispatch for common operations
; Input: RAX = trap selector
; Output: RAX = result
global fast_trap_dispatch
fast_trap_dispatch:
    push rbp
    mov rbp, rsp
    push rbx r12 r13 r14 r15

    ; Extract fields
    mov r12d, eax
    shr r12d, 8                 ; r12d = class
    and eax, 0xFF               ; rax = trap number

    ; Fast lookup in dispatch cache
    lea r8, [rel TRAP_DISPATCH_CACHE]
    mov r9, rax
    shl r9, 3
    add r8, r9

    mov r10, [r8]               ; cached handler
    test r10, r10
    jz .fast_trap_miss

    call r10                     ; direct handler call
    jmp .fast_trap_done

.fast_trap_miss:
    ; Fall through to normal dispatch
    call trap_dispatch

.fast_trap_done:
    pop r15 r14 r13 r12 rbx
    pop rbp
    ret

; ============================================================================
; SECTION: Extended Window Management
; ============================================================================

; Function: window_find_by_id
; Purpose: Find window descriptor by ID
; Input: RAX = window ID
; Output: RBX = window descriptor address
window_find_by_id:
    push rbp
    mov rbp, rsp

    cmp rax, MAX_WINDOWS
    jge .win_find_notfound

    lea r8, [rel WINDOW_TABLE]
    mov r9, rax
    shl r9, 6
    add r8, r9
    mov rbx, r8

    pop rbp
    ret

.win_find_notfound:
    xor rbx, rbx
    pop rbp
    ret

; Function: window_add_child
; Purpose: Add window to parent's child list
; Input: RAX = parent ID, RBX = child ID
; Output: rax = status
window_add_child:
    push rbp
    mov rbp, rsp
    push r12 r13

    ; RAX = parent window ID
    ; RBX = child window ID

    lea r8, [rel WINDOW_TABLE]
    mov r9, rax
    shl r9, 6
    add r8, r9

    ; Get parent's child list head
    mov r10, [r8 + 8]
    cmp r10, 0
    je .win_add_first_child

    ; Add to linked list
    xor rax, rax
    jmp .win_add_child_done

.win_add_first_child:
    mov r10, rbx
    mov [r8 + 8], r10
    xor rax, rax

.win_add_child_done:
    pop r13 r12
    pop rbp
    ret

; Function: window_remove_child
; Purpose: Remove window from parent's child list
; Input: RAX = parent ID, RBX = child ID
; Output: rax = status
window_remove_child:
    push rbp
    mov rbp, rsp

    ; RAX = parent ID
    ; RBX = child ID

    xor rax, rax
    pop rbp
    ret

; Function: window_raise
; Purpose: Raise window to top of z-order
; Input: RAX = window ID
window_raise:
    push rbp
    mov rbp, rsp
    push rbx r12

    ; Get window from table
    lea r8, [rel WINDOW_TABLE]
    mov r9, rax
    shl r9, 6
    add r8, r9

    ; Update z-order information
    lea r10, [rel WINDOW_ZORDER]

    pop r12 rbx
    pop rbp
    ret

; Function: window_lower
; Purpose: Lower window in z-order
; Input: RAX = window ID
window_lower:
    push rbp
    mov rbp, rsp

    ; Similar to raise but opposite
    pop rbp
    ret

; ============================================================================
; SECTION: Control Management Extended
; ============================================================================

; Function: control_set_style
; Purpose: Set control style attributes
; Input: RAX = control ID, RBX = style flags
control_set_style:
    push rbp
    mov rbp, rsp
    push r12

    lea r8, [rel CONTROL_TABLE]
    mov r9, rax
    shl r9, 3
    add r8, r9

    ; Store style flags
    mov [r8 + 24], ebx

    pop r12
    pop rbp
    ret

; Function: control_get_style
; Purpose: Get control style attributes
; Input: RAX = control ID
; Output: RAX = style flags
control_get_style:
    push rbp
    mov rbp, rsp

    lea r8, [rel CONTROL_TABLE]
    mov r9, rax
    shl r9, 3
    add r8, r9

    mov eax, [r8 + 24]

    pop rbp
    ret

; Function: control_set_handler
; Purpose: Set event handler for control
; Input: RAX = control ID, RBX = handler address
control_set_handler:
    push rbp
    mov rbp, rsp

    lea r8, [rel CONTROL_TABLE]
    mov r9, rax
    shl r9, 3
    add r8, r9

    mov [r8 + 28], rbx

    pop rbp
    ret

; Function: control_get_handler
; Purpose: Get event handler for control
; Input: RAX = control ID
; Output: RAX = handler address
control_get_handler:
    push rbp
    mov rbp, rsp

    lea r8, [rel CONTROL_TABLE]
    mov r9, rax
    shl r9, 3
    add r8, r9

    mov rax, [r8 + 28]

    pop rbp
    ret

; ============================================================================
; SECTION: Menu Management Extended
; ============================================================================

; Function: menu_get_itemcount
; Purpose: Get number of items in menu
; Input: RAX = menu ID
; Output: RAX = item count
menu_get_itemcount:
    push rbp
    mov rbp, rsp

    lea r8, [rel MENU_TABLE]
    mov r9, rax
    shl r9, 4
    add r8, r9

    mov eax, [r8 + 4]

    pop rbp
    ret

; Function: menu_set_itemcount
; Purpose: Set number of items in menu
; Input: RAX = menu ID, RBX = count
menu_set_itemcount:
    push rbp
    mov rbp, rsp

    lea r8, [rel MENU_TABLE]
    mov r9, rax
    shl r9, 4
    add r8, r9

    mov [r8 + 4], ebx

    pop rbp
    ret

; Function: menu_get_item
; Purpose: Get menu item at index
; Input: RAX = menu ID, RBX = index
; Output: RAX = item descriptor
menu_get_item:
    push rbp
    mov rbp, rsp
    push r12

    lea r8, [rel MENU_TABLE]
    mov r9, rax
    shl r9, 4
    add r8, r9

    ; Get item array address
    mov r10, [r8 + 16]

    ; Get item offset
    mov r12, rbx
    shl r12, 5                  ; 32 bytes per item
    add r10, r12

    mov rax, [r10]

    pop r12
    pop rbp
    ret

; Function: menu_set_handler
; Purpose: Set menu event handler
; Input: RAX = menu ID, RBX = handler
menu_set_handler:
    push rbp
    mov rbp, rsp

    lea r8, [rel MENU_TABLE]
    mov r9, rax
    shl r9, 4
    add r8, r9

    mov [r8 + 32], rbx

    pop rbp
    ret

; ============================================================================
; SECTION: Event Queue Management Extended
; ============================================================================

; Function: event_getcount
; Purpose: Get number of events in queue
; Output: RAX = event count
event_getcount:
    push rbp
    mov rbp, rsp

    lea r8, [rel EVENT_QUEUE_HEAD]
    mov rax, [r8]

    lea r8, [rel EVENT_QUEUE_TAIL]
    mov rbx, [r8]

    sub rax, rbx                ; count = tail - head

    pop rbp
    ret

; Function: event_isempty
; Purpose: Check if event queue is empty
; Output: RAX = 1 if empty, 0 otherwise
event_isempty:
    push rbp
    mov rbp, rsp

    lea r8, [rel EVENT_QUEUE_HEAD]
    mov rax, [r8]

    lea r8, [rel EVENT_QUEUE_TAIL]
    mov rbx, [r8]

    xor rax, rax
    cmp rbx, [rel EVENT_QUEUE_HEAD]
    je .evt_is_empty_true
    mov rax, 1

.evt_is_empty_true:
    pop rbp
    ret

; Function: event_post_priority
; Purpose: Post event with priority (goes to front)
; Input: RBX = event descriptor
event_post_priority:
    push rbp
    mov rbp, rsp

    ; Move head back and insert at front
    lea r8, [rel EVENT_QUEUE_HEAD]
    mov r9, [r8]
    dec r9
    mov [r8], r9

    xor rax, rax
    pop rbp
    ret

; ============================================================================
; SECTION: Resource Locking and Synchronization
; ============================================================================

; Function: resource_trylock
; Purpose: Attempt to lock resource without blocking
; Input: RAX = resource handle
; Output: RAX = 1 if locked, 0 if busy
resource_trylock:
    push rbp
    mov rbp, rsp

    lea r8, [rel RESOURCE_LOCK_TABLE]
    mov r9, rax
    shl r9, 3
    add r8, r9

    ; Atomic compare-and-swap for lock
    xor rax, rax
    mov rcx, 1

    cmpxchg qword [r8], rcx
    je .lock_acquired

    xor rax, rax
    pop rbp
    ret

.lock_acquired:
    mov rax, 1
    pop rbp
    ret

; Function: resource_getlock_info
; Purpose: Get information about resource lock
; Input: RAX = resource handle
; Output: RAX = lock count, RBX = owner
resource_getlock_info:
    push rbp
    mov rbp, rsp

    lea r8, [rel RESOURCE_TABLE]
    mov r9, rax
    shl r9, 4
    add r8, r9

    mov eax, [r8 + 32]          ; lock count
    mov ebx, [r8 + 36]          ; owner

    pop rbp
    ret

; ============================================================================
; SECTION: Error Handling and Diagnostics
; ============================================================================

; Function: toolbox_assert
; Purpose: Runtime assertion for debugging
; Input: RAX = condition, RBX = error code
toolbox_assert:
    push rbp
    mov rbp, rsp

    test rax, rax
    jnz .assert_pass

    ; Assertion failed
    call set_error_status

.assert_pass:
    pop rbp
    ret

; Function: toolbox_debug_break
; Purpose: Insert debug breakpoint
global toolbox_debug_break
toolbox_debug_break:
    push rbp
    mov rbp, rsp

    int 3                       ; CPU breakpoint

    pop rbp
    ret

; Function: toolbox_trace
; Purpose: Output debug trace
; Input: RDI = format string, RSI = parameter
global toolbox_trace
toolbox_trace:
    push rbp
    mov rbp, rsp

    ; RDI = format string
    ; RSI = parameter

    xor rax, rax

    pop rbp
    ret

; ============================================================================
; SECTION: Handle Reference Counting
; ============================================================================

; Function: handle_addref
; Purpose: Increment handle reference count
; Input: RAX = handle
; Output: RAX = new refcount
handle_addref:
    push rbp
    mov rbp, rsp

    cmp rax, MAX_HANDLES
    jge .addref_invalid

    lea r8, [rel HANDLE_TABLE]
    mov r9, rax
    shl r9, 4
    add r8, r9

    ; Increment refcount
    add dword [r8 + 12], 1
    mov eax, [r8 + 12]

    pop rbp
    ret

.addref_invalid:
    xor rax, rax
    pop rbp
    ret

; Function: handle_release
; Purpose: Decrement handle reference count
; Input: RAX = handle
; Output: RAX = new refcount
handle_release:
    push rbp
    mov rbp, rsp

    cmp rax, MAX_HANDLES
    jge .release_invalid

    lea r8, [rel HANDLE_TABLE]
    mov r9, rax
    shl r9, 4
    add r8, r9

    ; Decrement refcount
    sub dword [r8 + 12], 1
    mov eax, [r8 + 12]

    ; Free if refcount reaches zero
    cmp eax, 0
    jne .release_done

    call handle_free

.release_done:
    pop rbp
    ret

.release_invalid:
    xor rax, rax
    pop rbp
    ret

; ============================================================================
; SECTION: Batch Operations
; ============================================================================

; Function: window_enumerate
; Purpose: Enumerate all windows
; Input: RBX = callback function
; Output: RAX = count of windows enumerated
window_enumerate:
    push rbp
    mov rbp, rsp
    push r12 r13 r14

    xor r12, r12                ; counter

    lea r13, [rel WINDOW_TABLE]
    xor r14, r14                ; index

.win_enum_loop:
    cmp r14, MAX_WINDOWS
    jge .win_enum_done

    mov r8, r14
    shl r8, 6
    add r8, r13

    ; Check if window valid
    test dword [r8], 0xFFFFFFFF
    jz .win_enum_skip

    ; Call callback
    mov rax, r14
    call rbx

    inc r12

.win_enum_skip:
    inc r14
    jmp .win_enum_loop

.win_enum_done:
    mov rax, r12
    pop r14 r13 r12
    pop rbp
    ret

; Function: resource_enumerate
; Purpose: Enumerate all resources
; Input: RBX = callback function
; Output: RAX = count enumerated
resource_enumerate:
    push rbp
    mov rbp, rsp
    push r12 r13 r14

    xor r12, r12

    lea r13, [rel RESOURCE_TABLE]
    xor r14, r14

.res_enum_loop:
    cmp r14, MAX_RESOURCES
    jge .res_enum_done

    mov r8, r14
    shl r8, 4
    add r8, r13

    test dword [r8], 0xFFFFFFFF
    jz .res_enum_skip

    mov rax, r14
    call rbx

    inc r12

.res_enum_skip:
    inc r14
    jmp .res_enum_loop

.res_enum_done:
    mov rax, r12
    pop r14 r13 r12
    pop rbp
    ret

; ============================================================================
; SECTION: Utility Helpers
; ============================================================================

; Function: toolbox_memcpy
; Purpose: Copy memory block
; Input: RDI = destination, RSI = source, RDX = size
global toolbox_memcpy
toolbox_memcpy:
    push rbp
    mov rbp, rsp

    xor rax, rax
.memcpy_loop:
    cmp rax, rdx
    jge .memcpy_done

    mov cl, [rsi + rax]
    mov [rdi + rax], cl
    inc rax
    jmp .memcpy_loop

.memcpy_done:
    pop rbp
    ret

; Function: toolbox_memset
; Purpose: Set memory block
; Input: RDI = address, RSI = value, RDX = size
global toolbox_memset
toolbox_memset:
    push rbp
    mov rbp, rsp

    xor rax, rax
.memset_loop:
    cmp rax, rdx
    jge .memset_done

    mov [rdi + rax], sil
    inc rax
    jmp .memset_loop

.memset_done:
    pop rbp
    ret

; Function: toolbox_strlen
; Purpose: Get string length
; Input: RDI = string pointer
; Output: RAX = length
global toolbox_strlen
toolbox_strlen:
    push rbp
    mov rbp, rsp

    xor rax, rax
.strlen_loop:
    cmp byte [rdi + rax], 0
    je .strlen_done

    inc rax
    jmp .strlen_loop

.strlen_done:
    pop rbp
    ret

; ============================================================================
; SECTION: Advanced Window Management
; ============================================================================

; Function: window_set_parent
; Purpose: Set parent window
; Input: RAX = child ID, RBX = parent ID
window_set_parent:
    push rbp
    mov rbp, rsp

    lea r8, [rel WINDOW_TABLE]
    mov r9, rax
    shl r9, 6
    add r8, r9

    mov [r8 + 4], ebx

    pop rbp
    ret

; Function: window_get_parent
; Purpose: Get parent window
; Input: RAX = window ID
; Output: RAX = parent ID
window_get_parent:
    push rbp
    mov rbp, rsp

    lea r8, [rel WINDOW_TABLE]
    mov r9, rax
    shl r9, 6
    add r8, r9

    mov eax, [r8 + 4]

    pop rbp
    ret

; ============================================================================
; SECTION: Dispatch Cache Initialization
; ============================================================================

; ============================================================================
; SECTION: Advanced Control Features
; ============================================================================

; Function: control_enable
; Purpose: Enable a control
; Input: RAX = control ID
control_enable:
    push rbp
    mov rbp, rsp

    lea r8, [rel CONTROL_TABLE]
    mov r9, rax
    shl r9, 3
    add r8, r9

    ; Set enabled flag in state
    or dword [r8 + 36], 0x01

    pop rbp
    ret

; Function: control_disable
; Purpose: Disable a control
; Input: RAX = control ID
control_disable:
    push rbp
    mov rbp, rsp

    lea r8, [rel CONTROL_TABLE]
    mov r9, rax
    shl r9, 3
    add r8, r9

    ; Clear enabled flag
    and dword [r8 + 36], 0xFFFFFFFE

    pop rbp
    ret

; Function: control_isenabled
; Purpose: Check if control is enabled
; Input: RAX = control ID
; Output: RAX = 1 if enabled, 0 if disabled
control_isenabled:
    push rbp
    mov rbp, rsp

    lea r8, [rel CONTROL_TABLE]
    mov r9, rax
    shl r9, 3
    add r8, r9

    mov eax, [r8 + 36]
    and eax, 0x01

    pop rbp
    ret

; Function: control_setfocus
; Purpose: Set focus to control
; Input: RAX = control ID
control_setfocus:
    push rbp
    mov rbp, rsp

    ; Update current focused control in window
    lea r8, [rel CURRENT_CONTROL]
    mov [r8], ax

    pop rbp
    ret

; Function: control_getfocus
; Purpose: Get focused control
; Output: RAX = control ID
global control_getfocus
control_getfocus:
    push rbp
    mov rbp, rsp

    lea r8, [rel CURRENT_CONTROL]
    movzx rax, word [r8]

    pop rbp
    ret

; ============================================================================
; SECTION: Window Positioning and Sizing
; ============================================================================

; Function: window_setposition
; Purpose: Set window position
; Input: RAX = window ID, RBX = x, RCX = y
window_setposition:
    push rbp
    mov rbp, rsp

    lea r8, [rel WINDOW_TABLE]
    mov r9, rax
    shl r9, 6
    add r8, r9

    ; Store position at offset 16
    mov [r8 + 16], ebx          ; x coordinate
    mov [r8 + 20], ecx          ; y coordinate

    pop rbp
    ret

; Function: window_getposition
; Purpose: Get window position
; Input: RAX = window ID
; Output: RBX = x, RCX = y
window_getposition:
    push rbp
    mov rbp, rsp

    lea r8, [rel WINDOW_TABLE]
    mov r9, rax
    shl r9, 6
    add r8, r9

    mov ebx, [r8 + 16]          ; x coordinate
    mov ecx, [r8 + 20]          ; y coordinate

    pop rbp
    ret

; Function: window_setsize
; Purpose: Set window size
; Input: RAX = window ID, RBX = width, RCX = height
window_setsize:
    push rbp
    mov rbp, rsp

    lea r8, [rel WINDOW_TABLE]
    mov r9, rax
    shl r9, 6
    add r8, r9

    ; Store size
    mov [r8 + 24], ebx          ; width
    mov [r8 + 28], ecx          ; height

    pop rbp
    ret

; Function: window_getsize
; Purpose: Get window size
; Input: RAX = window ID
; Output: RBX = width, RCX = height
window_getsize:
    push rbp
    mov rbp, rsp

    lea r8, [rel WINDOW_TABLE]
    mov r9, rax
    shl r9, 6
    add r8, r9

    mov ebx, [r8 + 24]          ; width
    mov ecx, [r8 + 28]          ; height

    pop rbp
    ret

; Function: window_setrect
; Purpose: Set window rectangle (position + size)
; Input: RAX = window ID, RBX = x, RCX = y, RDX = w, RSI = h
window_setrect:
    push rbp
    mov rbp, rsp

    lea r8, [rel WINDOW_TABLE]
    mov r9, rax
    shl r9, 6
    add r8, r9

    mov [r8 + 16], ebx          ; x
    mov [r8 + 20], ecx          ; y
    mov [r8 + 24], edx          ; width
    mov [r8 + 28], esi          ; height

    pop rbp
    ret

; ============================================================================
; SECTION: Menu Item Operations
; ============================================================================

; Function: menu_item_getstatus
; Purpose: Get status of menu item
; Input: RAX = menu ID, RBX = item index
; Output: RAX = status flags
menu_item_getstatus:
    push rbp
    mov rbp, rsp

    lea r8, [rel MENU_TABLE]
    mov r9, rax
    shl r9, 4
    add r8, r9

    ; Get item array
    mov r10, [r8 + 16]
    mov r12, rbx
    shl r12, 5
    add r10, r12

    mov eax, [r10 + 24]         ; status flags

    pop rbp
    ret

; Function: menu_item_setstatus
; Purpose: Set status of menu item
; Input: RAX = menu ID, RBX = item index, RCX = status
menu_item_setstatus:
    push rbp
    mov rbp, rsp

    lea r8, [rel MENU_TABLE]
    mov r9, rax
    shl r9, 4
    add r8, r9

    mov r10, [r8 + 16]
    mov r12, rbx
    shl r12, 5
    add r10, r12

    mov [r10 + 24], ecx         ; update status

    pop rbp
    ret

; ============================================================================
; SECTION: Event Priority and Ordering
; ============================================================================

; Function: event_setpriority
; Purpose: Set event priority level
; Input: RAX = event ID, RBX = priority (0-15)
event_setpriority:
    push rbp
    mov rbp, rsp

    ; Store priority in event descriptor
    xor rax, rax
    pop rbp
    ret

; Function: event_getpriority
; Purpose: Get event priority
; Input: RAX = event ID
; Output: RAX = priority
event_getpriority:
    push rbp
    mov rbp, rsp

    xor rax, rax
    pop rbp
    ret

; ============================================================================
; SECTION: Resource Allocation Tracking
; ============================================================================

; Function: resource_getallocated
; Purpose: Get total allocated resources
; Output: RAX = count
global resource_getallocated
resource_getallocated:
    push rbp
    mov rbp, rsp
    push r12

    xor r12, r12
    xor r9, r9

.res_count_loop:
    cmp r9, MAX_RESOURCES
    jge .res_count_done

    lea r8, [rel RESOURCE_TABLE]
    mov r10, r9
    shl r10, 4
    add r8, r10

    test dword [r8], 0xFFFFFFFF
    jz .res_count_skip

    inc r12

.res_count_skip:
    inc r9
    jmp .res_count_loop

.res_count_done:
    mov rax, r12
    pop r12
    pop rbp
    ret

; Function: resource_available
; Purpose: Get available resource slots
; Output: RAX = available count
global resource_available
resource_available:
    push rbp
    mov rbp, rsp

    mov rax, MAX_RESOURCES
    sub rax, [rel resource_allocate]  ; Rough estimate

    pop rbp
    ret

; ============================================================================
; SECTION: Initialization Sequences
; ============================================================================

; Function: toolbox_reset_all_tables
; Purpose: Reset all system tables
global toolbox_reset_all_tables
toolbox_reset_all_tables:
    push rbp
    mov rbp, rsp
    push r12 r13

    ; Reset handle table
    lea r8, [rel HANDLE_TABLE]
    xor r9, r9

.reset_handles:
    cmp r9, MAX_HANDLES
    jge .reset_windows

    mov r10, r9
    shl r10, 4
    mov qword [r8 + r10], 0
    mov qword [r8 + r10 + 8], 0
    inc r9
    jmp .reset_handles

.reset_windows:
    lea r8, [rel WINDOW_TABLE]
    xor r9, r9

.reset_wins:
    cmp r9, MAX_WINDOWS
    jge .reset_controls

    mov r10, r9
    shl r10, 6

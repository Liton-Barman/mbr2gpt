; This is an entry point for our BBP code
;
; Program flow:
; 1. setup registers
; 2. set video mode to teletype (80 x 25)
; 3. enable A20 Gate
; 4. enable Protected Mode
; 5. setup segments
; 6. execute C main32() method which should do a long mode jump
; 7. execute C main64() method which should start up full long mode environment

%define ORG_LOC 0x7C00							; Initial position in memory (where MBR loads us)

[section .rodata]

[global gdt]									; Make GDT accessible from C
[global gdt_ptr]								; Make GDT pointer accessible from C

; Global Descriptor Table (GDT) used to do a Protected Mode jump
gdt:
	; Null Descriptor (selector: 0x00)
	dw 0x0000
	dw 0x0000
	db 0x00
	db 0x00
	db 0x00
	db 0x00

	; Code Descriptor (selector: 0x08)
	dw 0xffff		; Limit
	dw 0x0000		; Base (low word)
	db 0x00			; Base (high word low byte)
	db 0x9a			; Access byte
	db 0xcf			; Limit (high nibble, 4bits) + flags (nibble)
	db 0x00			; Base (high word high byte)

	; Data Descriptor (selector: 0x10)
	dw 0xffff		; Limit
	dw 0x0000		; Base (low word)
	db 0x00			; Base (high word low byte)
	db 0x92			; Access byte
	db 0xcf			; Limit (high nibble, 4bits) + flags (nibble)
	db 0x00			; Base (high word high byte)
gdt_end:

; GDT pointer
gdt_ptr:
	dw (gdt_end - gdt - 1)
	dd (gdt + 0x0000)

[section .text]
[global start16]									; Export start16 to linker
[extern main32]										; Import main32() from C
;[extern main64]									; Import main64() from C

; Remember in NASM it's:
; instruction destination, source

[bits 16]											; Real mode

start16:											; Our entry point
	xor eax, eax									; clear ax
	mov ss, ax										; set stack segment to zero (is it, i'm dumb in assembly?)
	mov sp, ORG_LOC									; set stack pointer to the begining of MBR location in memory
	mov es, ax										; zero-out extra segment
	mov ds, ax										; zero-out data segment

set_video:											; Set video mode
	mov ah, 0x00									; command: change video mode
	mov al, 0x03									; 3rd Mode -> 80x25
	int 0x10										; call video interrupt

set_a20:											; Enable A20 Gate to access high memory in protected mode (Fast A20)
	cli												; disable interrupts
	in al, 0x92										; read from io port 0x92
	test al, 0x02									; do some test
	out 0x90, al									; write to io port 0x90

load_gdt:											; Load Global Descriptor Table
	lgdt [gdt_ptr]									; gdt_ptr is an address to memory so we enclose it in []
	
protected_mode:										; Enter Protected Mode
	mov eax, cr0									; read from Control Register CR0
	or eax, 0x0001									; set Protected Mode bit
	mov cr0, eax									; write to Control Register CR
	jmp 0x8:start32									; do the magic jump to finalize Protected Mode setup

[bits 32]											; Protected mode

start32:											; Setup all the data segments
	mov eax, 0x0010									; selector 0x10 - data descriptor
	mov ss, eax										; set Stack Segment
	mov ds, eax										; set Data Segment
	mov es, eax										; set Extra Segment
	mov fs, eax										; set Data2 Segment
	mov gs, eax										; set Data3 Segment
	sti												; enable interrupts
	call main32										; call C function main32() (see: boot32/main32.c)
	cli												; disable interrupts

; If we can not do it in C we'll try to do it in ASM here:

;disable_paging:									; Disable paging
;	mov eax, cr0									; read from Control Register CR0
;	xor eax, 80000000								; clear Paging bit
;	mov cr0, eax									; write to Control Register CR
	
;enable_pae:										; Enable PAE
;	mov eax, cr4									; read from Control Registar CR4
;	or eax, 0x0010									; set PAE enabled bit

;ia32e_mode:										; Enter Long Mode
;	mov ecx, 0xC0000080								; set to work with EFER MSR
;	rdmsr 											; read EFER MSR
;	or edx, 0x80									; set Long mode enabled (LME) bit
;	wrmsr											; write EFER MSR

;enable_paging:
;	mov eax, cr0									; read from Control Register CR0
;	or eax, 80000000								; clear Paging bit
;	mov cr0, eax									; write to Control Register CR

;reload_gdt:										; Re-Load Global Descriptor Table
;	lgdt [gdt_ptr]									; gdt_ptr is an address to memory so we enclose it in []

;[bits 64]											; Long mode

;start64:											; Transfer controll to C
;	sti												; enable interrupts
;	call main64										; call C function main64() (see: boot64/main64.c)
;	cli												; disable interrupts
;	jmp $											; hang
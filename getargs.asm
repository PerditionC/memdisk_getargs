; Public domain tool to fetch the load arguments of a MEMDISK
; (virtual disk, created by SYSLINUX MEMDISK tool in int 15h
; memory space after booting with SYSLINUX / ISOLINUX / ...
; to simplyfy booting non-Linux operating systems). Based
; on the IFMEMDSK tool. By Eric Auer 9/2004, BIOS mode and
; MAGIC mode and WHO feature added by Eric Auer 3/2005.

%define MAGIC 1	; magic M option, useful for boot loader ID check
		; by errorlevel.
%define WHO 0	; enable to have WHO=char variable in normal
		; output to report boot loader ID. Only useful
		; for boot loader IDs which are also ASCII chars.

; Returned NORMAL Errorlevel: (without / with Win32 running)
; 0 / 16 - 386 or better CPU but no MEMDISK
; 1 / 17 - A: is a MEMDISK
; 2 / 18 - B: is a MEMDISK
; 3 / 19 - C:, or to be more exact, the first harddisk, BIOS disk
;     number 80h, is a MEMDISK
; 253 - invalid command line argument (new 3/2005)
; 254 - the CPU is older than an 80286
; 255 - the CPU is an 80286 only, so no MEMDISK possible

%if MAGIC
; Returned MAGIC Errorlevel: If command line option M (upper case)
; given, errorlevel is the boot loader ID, 49 .. 52 ("1" .. "4"),
; if a syslinux 3.0+ family memdisk is found. If no memdisk or an
%if WHO
; older memdisk is found, errorlevel is 88 ("X") or the version of
%else
; older memdisk is found, errorlevel is 0 or the version of
%endif
; syslinux/memdisk found (at most 2, for 2.xx).
%endif

; Returned BIOS MODE Errorlevel: (check type of user-selected drive)
;      0  - no such drive
;  1..63  - drive is CHS with n sectors per track
; 65..127 - same, but drive supports LBA (64 would be LBA-only drive)
; Specify 0..1 for floppy, 2..9 for harddisks 80h..87h.


%imacro	FLAGCHECK 0
	pushf		; save
	push ax		; test value
	popf		; try to set flags
	pushf		; check what happened
	pop ax		; test results
	popf		; restore
%endmacro


	org 100h	; a .COM file

start:	mov si,81h
cmd:	lodsb
	cmp al,' '
	jz cmd
	cmp al,9
	jz cmd
	cmp al,13
	jbe memdsk	; CLASSIC mode: check for memdisks
	; cmp al,'?'	; implicit, all invalid args trigger help
	; jz help
%if MAGIC
	cmp al,'M'	; "undocumented" MAGIC mode: ask memdisk
	jz memdsk_magic	; for boot loader type, if memdisk found.
	cmp al,'m'	; "undocumented" MAGIC mode: ask memdisk
	jz memdsk_magic	; for boot loader type, if memdisk found.
%endif
	cmp al,'0'
	jb help		; invalid argument
	cmp al,'9'
	ja help		; invalid argument
	sub al,'0'
	cbw		; argument AX: drive number
	cmp al,2
	jb floppy	; floppy, or rather harddisk?
	add al,80h-2	; 2..9 -> 80h..87h
floppy:	jmp biosdsk	; NEW MODE: check BIOS disk properties


help:	mov ah,9	; string$ output
	mov dx,helpmsg	; help text
	int 21h		; DOS API
	mov ax,4cfdh	; return errorlevel 253
	int 21h		; DOS API - exit


%if MAGIC
memdsk_magic:
	mov byte [magjmp+1],0	; zap the jump-over-magic-errorlevel,
				; enable boot loader ID in errorlevel.
%endif

memdsk:	xor bp,bp	; errorlevel
	dec bp
	dec bp

	xor ax,ax	; try to zero all flags
	mov bx,0f000h	; bit mask for high bits
	FLAGCHECK
	and ax,bx	; high bits...
	cmp ax,bx	; ...stuck to 1? 80186 or older!
	jz known	; *** is186: errorlevel 254, PC XT
	inc bp		; next assumption: 286
	mov ax,bx	; try to set all high bits
	FLAGCHECK
	test ax,bx	; all stuck to 0? 80286!
	jz known	; *** is286: errorlevel 255, PC AT but no 386+
	inc bp		; next: 386, but no memdisk found yet.

is386:	inc bp		; assumption: errorlevel 1, A: is a memdisk
	mov dl,0	; A:
	call memdiskcheck
	jc known	; only return first match
	inc bp		; assumption: errorlevel 2, B: is a memdisk
	mov dl,1	; B:
	call memdiskcheck
	jc known	; only return first match
	inc bp		; assumption: errorlevel 3, "C:" is a memdisk
	mov dl,80h	; "C:"
	call memdiskcheck
	jc known	; only return first match
noABCmemdisk:
	xor bp,bp	; errorlevel 0, no memdisk but at least a 386.

known:	mov ax,bp	; fetch errorlevel
	cbw		; sign-extend AL to AX
	add ax,ax
	mov bx,ax
	mov ah,9	; string$ output ds:dx
	mov dx,echomsg
	int 21h
	mov dx,[cs:stringtable+bx]	; fetch appropriate message
; - done:
	mov ah,9	; string$ output ds:dx
	int 21h		; DOS API
	mov dx,memdisk	; write " MEMDISK." and carriage return, line break
	mov ah,9
	int 21h
	mov ax,bp	; fetch errorlevel	
	call WinCheck	; check for Win32, add 16 to errorlevel if found
%if MAGIC
magjmp:	jmp short skipmagic	; patch this to enable the next mov al,...
	mov al,[syslver]	; will be "X" or "1" ... "4"
skipmagic:
%endif
	mov ah,4ch	; leave program, errorlevel in AL
	int 21h		; DOS API


memdiskcheck:
	mov eax,454d0800h	; magic1 + AH=8 (get geometry)
	mov ecx,444d0000h	; magic2
	push dx
	mov edx,53490000h	; magic3 +
	pop dx			; ... drive number in DL
	mov ebx,3f4b0000h	; magic4
	int 13h			; BIOS DISK API
	shr eax,16		; ignore AX
	shr ebx,16		; ignore BX
	shr ecx,16		; ignore CX (geometry C/S)
	shr edx,16		; ignore DX (geometry H in DH)
	cmp ax,4d21h		; magic5
	jnz nomemdisk
	cmp cx,4d45h		; magic6
	jnz nomemdisk
	cmp dx,4944h		; magic7
	jnz nomemdisk
	cmp bx,4b53h		; magic8
	jnz nomemdisk

	mov al,[es:di+3]	; major version
	cmp al,3		; not supported before SYSLINUX 3.0
	jb oldsyslinux
	mov al,[es:di+26]	; boot loader ID
	mov [syslver],al	; "1".."4" for sys/pxe/iso/extlinux
oldsyslinux:
%if MAGIC && WHO		; have to save/restore value if both
	push ax
%endif
	push es
	push di
	les di,[es:di+12]
	call printcommandline
	pop di
	pop es
%if MAGIC && WHO
	pop ax
	mov [syslver],al	; "1".."4" for sys/pxe/iso/extlinux
%endif

	; ES:DI now points to a data structure...
	; dw bytes, dw version, dd disk address in RAM,
	; dd size in sectors, dd pointer to commandline,
	; dd old int 13h vector, dd old int 15h vector
	; dw old [40h:13h] low memory size value

	stc			; return success
	ret

nomemdisk:
	clc			; return failure
	ret


		dw pcxt, pcat	; entries -2 and -1 of stringtable!
stringtable	dw xmem, amem, bmem, cmem

echomsg	db "@echo $"
pcxt	db "8086, can't have$"	; 254
pcat	db "80286, can't have$"	; 255
xmem	db "found no$"	 	; (in A B HDA)	; 0 (or 16)
amem	db "A: is$"		; 1 (or 17)
bmem	db "B: is$"		; 2 (or 18)
cmem	db "1st harddisk is$"	; 3 (or 19)
memdisk	db " MEMDISK.",13,10,"$"

iswin	db "@echo Win/"		; "Win (16 bit)" or "Win (NT-ish)" or ...
winbits	db "32 DOS box!",13,10,"$"	; editable part
	; --- winbits	db "32 bit) DOS box!",13,10,"$"	; editable part
	; shorter: Win/16, Win/32 or Win/NT

WinCheck:
	push bx
	push cx
	push dx

	push ax
	mov ax,1683h	; get current virtual machine number
	xor bx,bx	; preset to 0 if no Win at all running
	int 2fh
	or bx,bx
	pop ax
	jnz IsWin

	push ax
	mov ax,1600h	; Win32 install check
	int 2fh
	test al,7fh	; 0 / 80 no Win32, 1 Win2, -1 Win2, 3.. Win 3..
	pop ax
	jnz IsWin

	push ax
	mov ax,160ah	; Win3+ version check
	int 2fh		; (modifies BX and CX as well)
	or ax,ax	; 0 means Win3+ version check supported
	pop ax
	jz IsWin
	; version is BH.BL for CPU type CX

	push ax
	mov ax,3306h	; get internal DOS version (DOS 5+)
	int 21h		; returns AL=-1 for older DOS versions
	cmp bx,3205h	; WinNT/2k/XP/... DOS boxes report version 5.50
	pop ax		; (modifies BX and DX as well)
	jnz WinChecked
	add al,16	; change errorlevel
	mov bx,"NT"	; WinNT family
	; --- mov dword [winbits+2],"-ish"	; not " bit", but "-ish" :-)
	jmp short WinIs32

IsWin:	add al,16	; change errorlevel

	push ax
	mov ax,1600h	; do Win32 install check
	int 2fh
	or al,al	; major version number, or (Win2) +1/-1
	pop ax
	mov bx,"32"	; assume Win32-ish mode
	jnz WinIs32	; ah is minor version number.
	mov bx,"16"	; not in enhanced / Win386 / Win32 mode
	; (the Win3.x 286 (standard mode) DOS extender has no version check)
WinIs32:
	mov word [winbits],bx	; not in enhanced / Win386 / Win32 mode
	push ax
	mov dx,iswin
	mov ah,9
	int 21h
	pop ax

WinChecked:
	pop dx
	pop cx
	pop bx
	ret



printcommandline:	; string at ES:DI, 0 terminated, space separated
; http://people.cs.uchicago.edu/~gmurali/gui/comboot/getargs.c skips over
; leading and trailing spaces and treats args without = inside as special.
	push ax
	push bx
	push bp
%if WHO
	jmp short dosyslver	; FIRST, create "SET WHO=loader" line
%endif

nextcl:	mov bx,setline+5	; target pointer
	xor bp,bp		; "no = yet"
skipcl:	mov al,[es:di]
	inc di
	xor ah,ah		; flag not in FD kernel config {} block 
	or al,al
	jz donecl
	cmp al,' '
	jz skipcl		; skip leading spaces

copycl:	
	or ah,ah		; skipping FD kernel config.sys lines { ... } ?
	jnz checkfdend
	cmp al,' '		; suppress control chars
	jb evil			; those are evil, skip them
	je donecl		; space found so print key=value
	cmp al,'{'		; skip FD kernel config.sys lines { ... }
	jnz notfd
	or ah, 1
	jmp evil
checkfdend:
	cmp al,'}'
	mov al,'}'		; ensure spaces aren't treated special
	jnz evil
	xor ah,ah
	jmp evil
notfd:
	cmp al,'='
	jnz nosign
issign:	inc bp			; found a = sign, remember that
nosign:	mov [bx],al		; save useful byte
	inc bx
evil:	mov al,[es:di]		; check next source byte
	inc di
	or al,al
	jz donecl
	jmp copycl

donecl:	cmp bx,setline+5
	jz nocl
	or bp,bp		; already saw a = sign? else add one!
	jnz hadsign
	mov word [bx],"=Y"
	inc bx
	inc bx
hadsign:
	mov word [bx],0a0dh	; 13,10 (carriage return, linefeed)
	mov byte [bx+2],'$'	; end of string
dosyslver:
	mov ah,9
	mov dx,setline
	int 21h			; print string to stdout
nocl:	dec di			; rewind
	mov al,[es:di]		; the byte which ended THIS argument
	or al,al		; end of the whole thing?
	jnz nextcl		; otherwise repeat for NEXT argument
	pop bp
	pop bx
	pop ax
	ret

%if WHO
setline	db "@SET WHO="		; first item: "@SET WHO=bootloaderID"
syslver	db "X",13,10,"$"	; BUFFER for strings follows
%else
syslver	db 0			; storage space for boot loader ID
setline	db "@SET "		; BUFFER for strings follows this
%endif
	; (will overwrite the biosdsk code in getargs mode, no problem)


biosdsk:			; check BIOS disk AX properties
	mov dl,al		; selected drive number
	push dx
	mov ah,8		; get geometry
	push es			; push di not needed here
	int 13h			; BIOS DISK API
	pop es			; pop di not needed here
	mov al,dl		; number of disks in this "category"
	pop dx
	jc nosuchdrive
	or al,al
	jz nosuchdrive
	and cl,63
	mov dh,cl		; intermediate result...
	push dx
	mov ax,4100h		; LBA presence check
	mov bx,55aah		; magic value
	int 13h			; BIOS DISK API
	pop dx			; ignore further register messing here
	cmp bx,0aa55h
	mov ax,nolbamsg
	jnz nolbadrive
	test cx,1
	jz nolbadrive
	mov ax,lbadrivemsg
	add dh,64		; flag LBA capability
nolbadrive:
	push dx
	mov dx,ax		; message
	mov ah,9		; show string$
	int 21h			; DOS API
	pop dx
	mov al,dh		; errorlevel
	jmp short godos

nosuchdrive:
	mov ah,9		; show string$
	mov dx,nodrivemsg
	int 21h			; DOS API
	mov al,0		; return errorlevel 0
godos:	mov ah,4ch		; exit with errorlevel AH
	int 21h			; DOS API
	

nodrivemsg	db "No drive.",13,10,"$"
nolbamsg	db "Normal CHS drive.",13,10,"$"
lbadrivemsg	db "LBA-enabled drive.",13,10,"$"
	; PS: int 13.15 returned AH is 2 if with disk change detector


helpmsg	db "Public Domain. Finds MEMDISK, writes SET lines with MD params."
	db 13,10
	db "Returns: 0 no MD, 254/255 pre-386 CPU,",13,10
	db "  1-3 found MD on A:-C:, add 16 if inside WinXX",13,10
%if MAGIC	; save space: short help if magic on...
	db "GETARGS n: n=0/1/2/3-9 check A:/B:/1st-8th harddisk, not MD."
	db 13,10
	db "Returns: 0 none, 1-63 sectors, 64-127 LBA"
%else
	db "Or do 'GETARGS n': n=0/1 check A:/B: disk, "
	db   "n=2..9 check 0x80..0x87 harddisk.",13,10
	db "Returns: 0 no disk, 1..63 geometry (S), add 64 if LBA okay."
%endif
	db 13,10
%if MAGIC > WHO	; magic on, but who not (have to save space else)
	db "GETARGS M:",13,10
	db "Returns: 0-2 no/old MD, 3-? boot loader ID",13,10
%endif
%if MAGIC && WHO
	db "GETARGS M: Returns MD 3+ boot loader ID.",13,10
%endif
	db "$"


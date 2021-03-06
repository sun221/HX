
;--- scans DOS MCB chain to find installed instances of hdpmi
;--- will only find instances of current version!

	.486

	include hdpmi.inc
	include external.inc

	option proc:private

OPT_PTES equ 1	;display PTEs

	@seg _ITEXT16

GDTSEG segment para use16 public 'CODE'
endofgdtseg label near
GDTSEG ends
GROUP16 group GDTSEG

_ITEXT16 segment

	@ResetTrace

;--- convert word to string (decimal)
;--- @rprintf knows hexadecimal only!

itoa proc stdcall uses bx di number:word, buffer:word

	mov di, 10
	mov ax, number
	mov bx,buffer
	add bx,7
	mov BYTE PTR ss:[bx],0
	dec bx
nextdigit:
	xor dx, dx
	div di
	add dl,'0'
	mov ss:[bx],dl
	dec bx
	and ax, ax
	jne nextdigit
	inc bx
	mov ax,bx
	ret
itoa endp

;--- copy memory via int 15h, ah=87h
;--- esi=src, edi=dst, cx=size

copymem proc uses es si
	sub sp,2*8	;room for entries 4+5

	shld eax,edi,16	;push dst descriptor
	mov dl,al
	mov dh,093h
	mov al,0
	push ax
	push dx
	push di
	push cx

	shld eax,esi,16	;push src descriptor
	mov dl,al
	mov al,0
	push ax
	push dx
	push si
	push cx
	add esi,ecx

	xor eax,eax		;push entries 0+1
	push eax
	push eax
	push eax
	push eax

	push ss
	pop es
	mov si,sp
	shr cx,1		; convert to words
	clc
	mov ah,87h
	int 15h
	lea esp,[esp+6*8]
	ret

copymem endp

;--- print Page Directory (physical address in ESI)

printpd proc stdcall uses esi edi fOptions:word

local cnt:word
local base:word
local buffer[1024]:dword
local buffer2[1024]:dword

	@rprintf <"   page directory:",lf>
	mov di, ss
	movzx edi,di
	shl edi,4
	lea bx,buffer
	movzx ebx,bx
	add edi,ebx
	mov cx,sizeof buffer
	call copymem
	mov cx,0
	lea di,buffer
	.repeat
		mov base,cx
		mov eax,ss:[di]
		.if (al & 1)
;--- count number of present PTEs in PDE
			pushad
			mov esi, eax
			and si,0F000h
			mov di, ss
			movzx edi,di
			shl edi,4
			lea bx,buffer2
			movzx ebx,bx
			add edi,ebx
			push cx
			mov cx,sizeof buffer2
			call copymem
			pop cx
			lea di,buffer2
			.if (cx == 0)			;don't count conventional memory + HMA
				mov cx,256+16
				add di,4*(256+16)
			.else
				mov cx,0
			.endif
			mov cnt,0
			.repeat
				mov eax, ss:[di]
				.if al & 1
					inc cnt
					.if fOptions & OPT_PTES
						movzx edx,base
						shl edx,22
						movzx ebx,cx
						shl ebx,12
						lea edx,[edx+ebx]
						lea ebx,[edx+1000h-1]
						@rprintf <"     %lX-%lX: %lX",lf>,edx,ebx,eax
					.endif
				.endif
				add di,sizeof dword
				inc cx
			.until cx == 1024
			popad
			movzx edx,cx
			shl edx,22
			lea ebx,[edx+400000h-1]
			.if (cx == 0)
				add edx,(256+16) shl 12
			.endif
			@rprintf <"   %lX-%lX: %lX [">,edx,ebx,eax
			invoke itoa, cnt, addr buffer2
			@rprintf <"%s pages]",lf>, ss, ax
		.endif
		add di,sizeof dword
		inc cx
	.until cx == 1024
	ret
printpd endp

;--- print mode flags

printmode proc
	test si, FM_RESIDENT
	jz @F
	@rprintf " resident"
@@:
	test si, FM_IVTVECS
	jz @F
	@rprintf " modIRQs"
@@:
	test si, FM_DISABLED
	jz @F
	@rprintf " disabled"
@@:
	test si, FM_CLONE
	jz @F
	@rprintf " clone"
@@:
	test si, FM_INIT
	jz @F
	@rprintf " initialized"
@@:
	ret
printmode endp

;--- print hdpmi version
;--- in: ES:DI -> hdpmi string

printversion proc
local buffer1[8]:byte
local buffer2[8]:byte
	@rprintf "hdpmi"
	.if byte ptr es:[di+7]
		@rprintf "32"
	.else
		@rprintf "16"
	.endif
	movzx cx,byte ptr es:[di+5]
	invoke itoa, cx, addr buffer1
	push ax
	movzx cx,byte ptr es:[di+6]
	invoke itoa, cx, addr buffer2
	pop cx
	@rprintf <" v%s.%s">, ss, cx, ss, ax
	ret
printversion endp

printlocation proc
;--- get name of PSP at [MCB+8]
	mov cx,es
	mov es,bx
	mov ax,es:[1]
	dec ax
	mov es,ax
	push 0
	push dword ptr es:[12]
	push dword ptr es:[8]
	mov es,cx
	@rprintf <" instance found at %X [%s]",lf>, es,ss,sp
	add sp,4+4+2
	ret
printlocation endp

;--- display global variables in conv memory of an instance
;--- inp: AX=hdpmi instance

checkinstance proc stdcall uses es bx si di wInst:word, fOptions:word

local buffer[8]:byte

	mov bx,es
	mov es,ax
	mov di,offset logo
	mov si,di
	mov cx,llogo
	push di
	repz cmpsb
	pop di
	jnz noinstance
	assume es:GROUP16
	inc wInst
	invoke itoa, wInst, addr buffer
	@rprintf "%s. ", ss, ax

	call printversion
	call printlocation
	movzx ax,cApps
	@rprintf <"   host stack=%lX, Clients=%X, TLB=%X, rmStack=%X:%X",lf>, dwHostStack, ax, wSegTLB, v86iret.rSS, v86iret.rSP
	@rprintf <"   hostPSP=%X, hostSeg=%X, envFlags=%X",lf>, wHostPSP, wHostSeg, wEnvFlags
	@rprintf <"   CR3=%lX, GDT=%lX, IDT=%lX, LDT=%lX",lf>, v86topm._cr3, pdGDT.dwBase, pdIDT.dwBase, dwLDTAddr
	mov si, word ptr fMode
	@rprintf <"   mode=%X [">, si
	call printmode
	@rprintf <" ]",lf>
	mov esi, v86topm._cr3
	invoke printpd, fOptions
	assume es:nothing
	mov ax,1
	ret
noinstance:
	cmp cx,2
	ja @F
	call printversion
	call printlocation
@@:
	xor ax,ax
	ret
checkinstance endp

;--- scan DOS memory for hdpmi instances

main proc public

local fOptions:word

	mov fOptions,0
	mov si,80h
	movzx cx, byte ptr es:[si]
	inc si
	.while cx
		mov al,es:[si]
		dec cx
		inc si
		.if cx && (al == '/' || al == '-')
			mov al,es:[si]
			or al,20h
			.if al == 'p'
				or fOptions, OPT_PTES
			.elseif al == '?'
				@rprintf <"HDPMIST displays states of currently loaded HDPMI instances",lf>
				@rprintf <"usage: HDPMIST [options]",lf>
				@rprintf <"options are:",lf>
				@rprintf <"  -? display this help",lf>
				@rprintf <"  -p display PTEs",lf>
				jmp exit
			.else
				dec si
				@rprintf <"unknown option %s",lf>,es,si
				jmp exit
			.endif
			dec cx
			inc si
		.endif
	.endw

	mov ax,5802h			;get umb link status
	int 21h
	xor ah,ah
	push ax
	mov ax,5803h			;link umbs
	mov bx,0001h
	int 21h
	mov ah,52h
	int 21h
	mov es,es:[bx-2]
	xor si,si
	xor bx,bx
	.while (byte ptr es:[bx] != 'Z')
		mov ax,es
		inc ax
		.if (ax == es:[bx+1])	;PSP MCB?
			add ax,10h			;skip PSP
			mov cx,cs
			.if (ax != cx)		;skip our instance!
				invoke checkinstance, si, fOptions
				add si,ax
			.endif
		.elseif word ptr es:[bx+1] != 0 && word ptr es:[bx+3] > 20h
			add ax,20h		;a clone has no PSP, but a preceding 200h real-mode stack!
			invoke checkinstance, si, fOptions
			add si, ax
		.endif
		mov ax,es:[bx+3]
		mov cx,es
		add ax,cx
		inc ax
		mov es,ax
	.endw
	pop bx				;restore umb link status
	mov ax,5803h
	int 21h
	and si,si
	jnz @F
	@rprintf <"no hdpmi v",@CatStr(!"%?VERMAJOR!.%?VERMINOR!")," instance found",lf>
@@:
exit:
	ret

main endp

	public mystart

mystart:
	cld
	push cs
	pop ds
;--- free unused dos mem 
	mov bx,ss
	mov cx,es
	sub bx,cx
	mov cx,sp
	shr cx,4
	add bx,cx
	mov ah,4Ah
	int 21h
	call main
error:
	mov ax,4C00h
	int 21h


_ITEXT16 ends

	end mystart

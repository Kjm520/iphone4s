	.def	@feat.00;
	.scl	3;
	.type	0;
	.endef
	.globl	@feat.00
@feat.00 = 0
	.intel_syntax noprefix
	.file	"add.c"
	.def	add;
	.scl	2;
	.type	32;
	.endef
	.text
	.globl	add                             # -- Begin function add
	.p2align	4
add:                                    # @add
.seh_proc add
# %bb.0:
	push	rax
	.seh_stackalloc 8
	.seh_endprologue
	mov	dword ptr [rsp + 4], edx
	mov	dword ptr [rsp], ecx
	mov	eax, dword ptr [rsp]
	add	eax, dword ptr [rsp + 4]
	.seh_startepilogue
	pop	rcx
	.seh_endepilogue
	ret
	.seh_endproc
                                        # -- End function
	.def	main;
	.scl	2;
	.type	32;
	.endef
	.globl	main                            # -- Begin function main
	.p2align	4
main:                                   # @main
.seh_proc main
# %bb.0:
	sub	rsp, 40
	.seh_stackalloc 40
	.seh_endprologue
	mov	dword ptr [rsp + 36], 0
	mov	ecx, 2
	mov	edx, 3
	call	add
	nop
	.seh_startepilogue
	add	rsp, 40
	.seh_endepilogue
	ret
	.seh_endproc
                                        # -- End function
	.section	.debug$S,"dr"
	.p2align	2, 0x0
	.long	4                               # Debug section magic
	.long	241
	.long	.Ltmp1-.Ltmp0                   # Subsection size
.Ltmp0:
	.short	.Ltmp3-.Ltmp2                   # Record length
.Ltmp2:
	.short	4353                            # Record kind: S_OBJNAME
	.long	0                               # Signature
	.byte	0                               # Object name
	.p2align	2, 0x0
.Ltmp3:
	.short	.Ltmp5-.Ltmp4                   # Record length
.Ltmp4:
	.short	4412                            # Record kind: S_COMPILE3
	.long	0                               # Flags and language
	.short	208                             # CPUType
	.short	23                              # Frontend version
	.short	1
	.short	2
	.short	0
	.short	23012                           # Backend version
	.short	0
	.short	0
	.short	0
	.asciz	"clang version 23.1.2 (https://github.com/llvm/llvm-project 85ac560262434c9ccfc0c183ec22d4138ed647fb)" # Null-terminated compiler version string
	.p2align	2, 0x0
.Ltmp5:
.Ltmp1:
	.p2align	2, 0x0
	.addrsig
	.addrsig_sym add

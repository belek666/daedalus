#define ABI_EABI64
#include "as_reg_compat.h"

//The top two defines needs to be adjusted depending on how gCPUState struct is formated in CPU.h!! //Corn
//
#define _C0_Count	(0x100 + 9 * 4)	//CPU_Control_base + 9*8(64bit regs) or 9*4(32bit regs)
#define _AuxBase	0x280	//Base pointer to Aux regs
#define _CurrentPC	(_AuxBase + 0x00)
#define _TargetPC	(_AuxBase + 0x04)
#define _Delay		(_AuxBase + 0x08)
#define _StuffToDo	(_AuxBase + 0x0c)
#define _MultLo		(_AuxBase + 0x10)
#define _MultHi		(_AuxBase + 0x18)
#define _Temp1		(_AuxBase + 0x20)
#define _Temp2		(_AuxBase + 0x28)
#define _Temp3		(_AuxBase + 0x30)
#define _Temp4		(_AuxBase + 0x38)
#define _Events		(_AuxBase + 0x40)

	.set noat

	.extern HandleException_extern
	.extern CPU_UpdateCounter
	.extern IndirectExitMap_Lookup
	.extern g_MemoryLookupTableReadForDynarec
	.extern Write64BitsForDynaRec
	.extern Write32BitsForDynaRec
	.extern Write16BitsForDynaRec
	.extern Write8BitsForDynaRec
	.extern CPU_HANDLE_COUNT_INTERRUPT


	.global _EnterDynaRec
	.global _ReturnFromDynaRec
	.global _DirectExitCheckNoDelay
	.global _DirectExitCheckDelay
	.global _IndirectExitCheck
	.global _ReturnFromDynaRecIfStuffToDo
	.global _DaedalusICacheInvalidate

	.global _ReadBitsDirect_u8
	.global _ReadBitsDirect_s8
	.global _ReadBitsDirect_u16
	.global _ReadBitsDirect_s16
	.global _ReadBitsDirect_u32
	.global _ReadBitsDirect_u64

	.global _ReadBitsDirectBD_u8
	.global _ReadBitsDirectBD_s8
	.global _ReadBitsDirectBD_u16
	.global _ReadBitsDirectBD_s16
	.global _ReadBitsDirectBD_u32
	.global _ReadBitsDirectBD_u64
	
	.global _WriteBitsDirect_u64
	.global _WriteBitsDirect_u32
	.global _WriteBitsDirect_u16
	.global _WriteBitsDirect_u8
	.global _WriteBitsDirectBD_u64
	.global _WriteBitsDirectBD_u32
	.global _WriteBitsDirectBD_u16
	.global _WriteBitsDirectBD_u8

	.global	_FloatToDouble
	.global	_DoubleToFloat
	.global	_printf_asm
	.global	_DMULTU
	.global	_DMULT
	.global	_DDIVU
	.global	_DDIV

    .data
exit_dynarec_text:
	.asciiz		"Exiting dynarec (PC is %08x StuffToDo is 0x%x)\n"
	.text
    .set push
    .set noreorder

.macro ins dest,src,pos,size
	sd	$t1, -32($sp)
	sd	$t0, -16($sp)

	li	$t0, ~(((1<<\size)-1)<<\pos)
	and	\dest, $t0
	sll	$t1, \src, \pos
	li	$t0, ((1<<\size)-1)<<\pos
	and	$t1, $t0
	or	\dest, $t1
	
	ld	$t1, -32($sp)
	ld	$t0, -16($sp)	
.endm

.macro ext dest,src,pos,size
	sd	$t0, -16($sp)
	srl	\dest, \src, \pos
	li	$t0, ((1 << \size) - 1 )
	and	\dest, $t0
	ld	$t0, -16($sp)
.endm

#######################################################################################
#    Invalidate a1 bytes of icache from a0
#	a0 - the base address of the memory to invalidate in the icache
#	a1 - the number of bytes to invalidate
_DaedalusICacheInvalidate:

	addiu		$v0, $0, 0xffc0			# v0 = ~63

	# Store base+size(-1) in a1
	addu		$a1, $a1, $a0
	addiu		$a1, $a1, -1

	# Truncate 'start' pointer down to nearest 64 bytes boundary
	and			$a0, $a0, $v0

	# Truncate 'end' pointer down to nearest 64 bytes boundary
	and			$a1, $a1, $v0

	# Do while current < end
invalidate_next:
	#sync.l
	#cache 		0x18, 0($a0)
	sync.l
	sync.p
	cache		0x0B, 0($a0)					# 8 is for icache invalidate
	bne			$a0, $a1, invalidate_next		# Keep looping until
	addiu		$a0, $a0, 64

	jr			$ra
	nop

#######################################################################################
#
#	a0 - fragment function to enter
#	a1 - gCPUState base pointer
#	a2 - Memory base offset (i.e. g_pu8RamBase - 0x80000000 )
#	a3 - Memory upper bound (e.g. 0x80400000)
#
#
_EnterDynaRec:
	addiu	$sp, $sp, -160	# Push return address on the stack
	sq		$ra, 0($sp)
	sq		$fp, 16($sp)		# Store s8 - we use this as our base pointer
	sq		$s0, 32($sp)
	sq		$s1, 48($sp)
	sq		$s2, 64($sp)
	sq		$s3, 80($sp)
	sq		$s4, 96($sp)
	sq		$s5, 112($sp)
	sq		$s6, 128($sp)
	sq		$s7, 144($sp)

	or		$s7, $a2, $0	# Read address table
	or		$s6, $a3, $0	# Upper bound

	jr		$a0				# Jump to our target function
	or		$fp, $a1, $0	# set frame pointer to Emulated CPU registers

#######################################################################################
#	Check gCPUState.StuffToDo. If non-zero, performs any required handling then exits
#	the dynarec system. If the flag is zero this just returns immediately.
#	NB: As a significant optinisation the dynarec system patches the first two ops
#	of this function to return immediately in the case the gCPUState.StuffToDo is not set.
#
_ReturnFromDynaRecIfStuffToDo:

# Sanity checking logic
#	lw		$v0, _StuffToDo($fp)		# StuffToDo
#	bne		$v0, $0, exception_exit
#	nop
#	jr		$ra					# Just return back to caller
#	nop
#exception_exit:

	jal		HandleException_extern
	nop

# Fall through to this
#	j		_ReturnFromDynaRec
#	nop

#######################################################################################
#
_ReturnFromDynaRec:
	lq		$ra, 0($sp)		# Restore our return address
	lq		$fp, 16($sp)		# And s8
	lq		$s0, 32($sp)
	lq		$s1, 48($sp)
	lq		$s2, 64($sp)
	lq		$s3, 80($sp)
	lq		$s4, 96($sp)
	lq		$s5, 112($sp)
	lq		$s6, 128($sp)
	lq		$s7, 144($sp)
	jr		$ra
	addiu	$sp, $sp, +160

#######################################################################################
#	Check if we need to exit the dynarec system and jump out as necessary.
#	If we are ok to continue, this returns control to the calling code.
#	Calling this function updates the COUNT register with the specified number of cycles.
#	a0	- instructions executed
#	a1	- exit pc
_DirectExitCheckNoDelay:

	# The code below corresponds to CPU_UpdateCounter
	lw		$v0, _C0_Count($fp)		# COUNT register
	lw		$v1, _Events($fp)		# Events[0].mCount

	addu	$v0, $v0, $a0		# COUNT + ops_executed
	sw		$v0, _C0_Count($fp)		# COUNT = COUNT + ops_executed

	sw		$a1, _CurrentPC($fp) 	# CurrentPC
	sw		 $0, _Delay($fp)		# Delay = NO_DELAY

	subu	$v1, $v1, $a0		# Events[0].mCount - ops_executed
	blez	$v1, _DirectExitCheckCheckCount
	sw		$v1, _Events($fp)		# Events[0].mCount = Events[0].mCount - ops_executed

	jr		$ra					# Return back to caller
	nop

#######################################################################################
#	Check if we need to exit the dynarec system and jump out as necessary.
#	If we are ok to continue, this returns control to the calling code.
#	Calling this function updates the COUNT register with the specified number of cycles.
#	a0	- instructions executed
#	a1	- exit pc
#	a2	- target pc
_DirectExitCheckDelay:

	# The code below corresponds to CPU_UpdateCounter
	lw		$v0, _C0_Count($fp)		# COUNT register
	lw		$v1, _Events($fp)		# Events[0].mCount

	addu	$v0, $v0, $a0		# COUNT + ops_executed
	sw		$v0, _C0_Count($fp)		# COUNT = COUNT + ops_executed

	sw		$a1, _CurrentPC($fp) 	# CurrentPC
	sw		$a2, _TargetPC($fp) 	# TargetPC
	li		$v0, 1				# EXEC_DELAY
	sw		$v0, _Delay($fp)		# Delay

	subu	$v1, $v1, $a0		# Events[0].mCount - ops_executed
	blez	$v1, _DirectExitCheckCheckCount
	sw		$v1, _Events($fp)		# Events[0].mCount = Events[0].mCount - ops_executed

	jr		$ra
	nop

#######################################################################################
#	Utility routine for _DirectExitCheckXX.
#
_DirectExitCheckCheckCount:
	or		$s0, $ra, $0		# Keep track of return addresss
	jal		CPU_HANDLE_COUNT_INTERRUPT
	nop

	lw		$v0, _StuffToDo($fp)		# StuffToDo
	bne		$v0, $0, _ReturnFromDynaRec
	nop
	jr		$s0					# Return back to caller
	nop


#######################################################################################
#	Update counter. If StuffToDo flags is clear on return,
#	a0 - instructions executed
#	a1 - CIndirectExitMap pointer
#	a2 - exit pc (exit delay is always NO_DELAY)
_IndirectExitCheck:
	or		$s0, $a1, $0		# Keep track of map pointer
	or		$s1, $a2, $0		# and the exit pc

	# Can avoid these until _ReturnFromDynaRec?
	sw		$a2, _CurrentPC($fp) 	# CurrentPC
	jal		CPU_UpdateCounter	# a0 holds instructions executed
	sw		$0,  _Delay($fp)		# Delay (NO_DELAY)

	lw		$v0, _StuffToDo($fp)		# StuffToDo
	bne		$v0, $0, _ReturnFromDynaRec
	nop

	or		$a0, $s0, $0		# p_map
	jal		IndirectExitMap_Lookup
	or		$a1, $s1, $0		# exit_pc

	# $v0 holds pointer to indirect target. If it's 0, it means it's not compiled yet
	beq		$v0, $0,  _ReturnFromDynaRec
	nop

	jr		$v0
	nop


#######################################################################################
#	u32 ret = u32( *(T *)FuncTableReadAddress( address ) );
#	_ReturnFromDynaRecIfStuffToDo( 0 );
#	return ret;
#
# a0 address (pre-swizzled)
# a1 current_pc
#
.macro READ_BITS	function, load_instruction
\function:

	sw		$ra, _Temp1($fp) 	# Temp storage

	srl		$v1, $a0, 0x12
	sll		$v1, $v1, 0x3	# * 8 to index the two pointer struct
	la		$v0, g_MemoryLookupTableReadForDynarec
	lw		$v0, 0($v0)			# The above is a pointer to our table
	addu	$v1, $v1, $v0
	lw		$v0, 4($v1)	#offset 4 to get the second pointer

	jalr	$v0
	sw		$a1, _CurrentPC($fp) 	# CurrentPC

	jal		_ReturnFromDynaRecIfStuffToDo
	move	$a0,$0

	lw		$ra, _Temp1($fp) 	# Temp storage

	jr		$ra
	\load_instruction	$v0, 0($v0)		# e.g. lbu, lhu, lw etc

.endm

.macro READ_BITS_BD	function, load_instruction
\function:

	sw		$ra, _Temp1($fp) 	# Temp storage
	sw		$a1, _CurrentPC($fp) 	# CurrentPC

	srl		$v1, $a0, 0x12
	sll		$v1, $v1, 0x3	# * 8 to index the two pointer struct
	la		$v0, g_MemoryLookupTableReadForDynarec
	lw		$v0, 0($v0)			# The above is a pointer to our table
	addu	$v1, $v1, $v0
	lw		$v0, 4($v1)	#offset 4 to get the second pointer

	li		$v1, 1				# EXEC_DELAY
	jalr	$v0
	sw		$v1, _Delay($fp)		# Delay

	jal		_ReturnFromDynaRecIfStuffToDo
	move	$a0,$0

	sw		$0, _Delay($fp)		# Delay <- NO_DELAY

	lw		$ra, _Temp1($fp) 	# Temp storage

	jr		$ra
	\load_instruction	$v0, 0($v0)		# e.g. lbu, lhu, lw etc

.endm

	READ_BITS _ReadBitsDirect_u8, lbu
	READ_BITS _ReadBitsDirect_s8, lb
	READ_BITS _ReadBitsDirect_u16, lhu
	READ_BITS _ReadBitsDirect_s16, lh
	READ_BITS _ReadBitsDirect_u32, lw
	READ_BITS _ReadBitsDirect_u64, ld
	
	READ_BITS_BD _ReadBitsDirectBD_u8, lbu
	READ_BITS_BD _ReadBitsDirectBD_s8, lb
	READ_BITS_BD _ReadBitsDirectBD_u16, lhu
	READ_BITS_BD _ReadBitsDirectBD_s16, lh
	READ_BITS_BD _ReadBitsDirectBD_u32, lw
	READ_BITS_BD _ReadBitsDirectBD_u64, ld

#######################################################################################
#	These functions handle writing a value out to memory.
#	They set up the PC (and optionally the branch delay flag for the BD versions)
#	After the memory has been written, _ReturnFromDynaRecIfStuffToDo is called,
#	which returns control back to the interpreter in the case that an exception
#	was triggered.
#
# a0 address (pre-swizzled)
# a1 value
# a2 current_pc
#
_WriteBitsDirect_u64:
	sw		$ra, _Temp1($fp) 	# Temp storage

	jal		Write64BitsForDynaRec
	sw		$a2, _CurrentPC($fp) 	# CurrentPC

	jal		_ReturnFromDynaRecIfStuffToDo
	move	$a0,$0

	lw		$ra, _Temp1($fp) 	# Temp storage
	jr		$ra
	nop

_WriteBitsDirectBD_u64:
	sw		$ra, _Temp1($fp) 	# Temp storage

	sw		$a2, _CurrentPC($fp) 	# CurrentPC
	li		$v1, 1				# EXEC_DELAY

	jal		Write64BitsForDynaRec
	sw		$v1, _Delay($fp)		# Delay

	jal		_ReturnFromDynaRecIfStuffToDo
	move	$a0,$0

	lw		$ra, _Temp1($fp) 	# Temp storage
	jr		$ra
	sw		$0, _Delay($fp)		# Delay <- NO_DELAY

_WriteBitsDirect_u32:
	sw		$ra, _Temp1($fp) 	# Temp storage

	jal		Write32BitsForDynaRec
	sw		$a2, _CurrentPC($fp) 	# CurrentPC

	jal		_ReturnFromDynaRecIfStuffToDo
	move	$a0,$0

	lw		$ra, _Temp1($fp) 	# Temp storage
	jr		$ra
	nop

_WriteBitsDirectBD_u32:
	sw		$ra, _Temp1($fp) 	# Temp storage

	sw		$a2, _CurrentPC($fp) 	# CurrentPC
	li		$v1, 1				# EXEC_DELAY

	jal		Write32BitsForDynaRec
	sw		$v1, _Delay($fp)		# Delay

	jal		_ReturnFromDynaRecIfStuffToDo
	move	$a0,$0

	lw		$ra, _Temp1($fp) 	# Temp storage
	jr		$ra
	sw		$0, _Delay($fp)		# Delay <- NO_DELAY

_WriteBitsDirect_u16:
	sw		$ra, _Temp1($fp) 	# Temp storage

	jal		Write16BitsForDynaRec
	sw		$a2, _CurrentPC($fp) 	# CurrentPC

	jal		_ReturnFromDynaRecIfStuffToDo
	move	$a0,$0

	lw		$ra, _Temp1($fp) 	# Temp storage
	jr		$ra
	nop


_WriteBitsDirectBD_u16:
	sw		$ra, _Temp1($fp) 	# Temp storage

	sw		$a2, _CurrentPC($fp) 	# CurrentPC
	li		$v1, 1				# EXEC_DELAY

	jal		Write16BitsForDynaRec
	sw		$v1, _Delay($fp)		# Delay

	jal		_ReturnFromDynaRecIfStuffToDo
	move	$a0,$0

	lw		$ra, _Temp1($fp) 	# Temp storage
	jr		$ra
	sw		$0, _Delay($fp)		# Delay <- NO_DELAY

_WriteBitsDirect_u8:
	sw		$ra, _Temp1($fp) 	# Temp storage

	jal		Write8BitsForDynaRec
	sw		$a2, _CurrentPC($fp) 	# CurrentPC

	jal		_ReturnFromDynaRecIfStuffToDo
	move	$a0,$0

	lw		$ra, _Temp1($fp) 	# Temp storage
	jr		$ra
	nop

_WriteBitsDirectBD_u8:
	sw		$ra, _Temp1($fp) 	# Temp storage
	sw		$a2, _CurrentPC($fp) 	# CurrentPC
	li		$v1, 1				# EXEC_DELAY

	jal		Write8BitsForDynaRec
	sw		$v1, _Delay($fp)		# Delay

	jal		_ReturnFromDynaRecIfStuffToDo
	move	$a0,$0

	lw		$ra, _Temp1($fp) 	# Temp storage
	jr		$ra
	sw		$0, _Delay($fp)		# Delay <- NO_DELAY

#######################################################################################
/**
 * convert float to double
 * double FloatToDouble(float a);
 *
 * input: a0
 * output: v0,v1
 * clobber: a0,a1
 */
_FloatToDouble:
	ext		$a1, $a0, 23, 8			/* a1 = (a0 >> 23) & 0xFF */
	beqz	$a1, ftod_denormal		/* if (a1==0) goto ftod_denormal */
	addiu	$v0, $a1, (-0x7F+0x3FF)	/* v0 = a1 - 0x7F + 0x3FF */
	xori	$a1, $a1, 0xFF			/* a1 = a1 ^ 0xFF */
	li		$v1, 0x7FF				/* v1 = 0x7FF */
	movz	$v0, $v1, $a1			/* v0 = (a1==0) ? v1 : v0 */
	ext		$v1, $a0,  3, 20		/* v1 = (a0 >> 3 ) & 0x00FFFFF */
	ins		$v1, $v0, 20, 11		/* v1 = (v1 & 0x800FFFFF) | ((v0<<20) & 0x7FF00000) */
	sll		$v0, $a0, 29			/* v0 = (a0 << 29) */
	srl		$a0, $a0, 31			/* a0 = (a0 >> 31) & 1 */
	ins		$v1, $a0, 31, 1			/* v1 = (v1 & 0x7FFFFFFF) | ((a0<<31) & 0x80000000) */
	jr		$ra						/* return */
	nop

ftod_denormal:
	sll		$v0, $a0, 9				/* v0 = a0 << 9 */
	beqzl	$v0, ftod_zero			/* if (v0==0) goto ftod_zero */
	move	$v1, $zero				/* v1 = 0 */
	li		$v1, 0x380				/* v1 = 0x380 */
	
	move	$a1, $v0
	srl		$a1, $a1, 31
	bgtz	$a1, _clz_no_zeros
	move	$a1, $zero
	plzcw	$a1, $v0
	addi	$a1, $a1, 1
_clz_no_zeros:	
	#clz		$a1, $v0				/* a1 = clz(v0) */
	
	subu	$v0, $v1, $a1			/* v0 = v1 - v0 = 0x380 - clz(a1) */
	sllv	$a1, $a0, $a1			/* a1 = a0 << a1 */
	ext		$v1, $a1,  2, 20		/* v1 = (a1 >> 2 ) & 0x00FFFFF */
	ins		$v1, $v0, 20, 11		/* v1 = (v1 & 0x800FFFFF) | ((v0<<20) & 0x7FF00000) */
	sll		$v0, $a1, 30			/* v0 = (a1 << 30) */
ftod_zero:
	srl		$a0, $a0, 31			/* a0 = (a0 >> 31) & 1 */
	ins		$v1, $a0, 31, 1			/* v1 = (v1 & 0x7FFFFFFF) | ((a0<<31) & 0x80000000) */
	jr		$ra						/* return */
	nop

#######################################################################################
/**
 * convert double to float
 * float DoubleToFloat(double a);
 * input: a0,a1
 * output: v0
 * clobber: v0,v1,a2,a3
 */
_DoubleToFloat:
	ext		$a2, $a1, 20, 11		/* a2 = (a1>>20) & 0x000007FF */
	beqz	$a2, dtof_zero			/* if (a2==0) goto dtof_zero */
	xori	$a3, $a2, 0x7FF			/* a3 = a2 ^ 0x7FF */
	beqz	$a3, dtof_naninf		/* if (a3==0) goto dtof_naninf */
	addiu	$a3, $a2, (+0x7F-0x3FF)	/* a3 = a2 + 0x7F - 0x3FF */
	blez	$a3, dtof_denormal		/* if (a3<=0) goto dtof_denormal */
	addiu	$v1, $a3, -0xFE			/* v1 = a3 - 0xFE */
	bgtz	$v1, dtof_inf			/* if (v1 > 0) goto dtof_inf */
	move	$v0, $zero				/* v0 = 0 */

	srl		$v0, $a0, 29			/* v0 = (a0>>29) & 0x00000007 */
	ins		$v0, $a1, 3, 20			/* v0 = (v0 & 0xFF800007) | ((a1 & 0FFFFF)<<3) */
	beqz	$v1, dtof_inf_normal	/* if (v1==0) goto dtof_inf_normal */
dtof_normal:
	srl		$v1, $a1, 31			/* v1 = (a1>>31) & 1 */
dtof_normal2:
	ins		$v0, $v1, 31, 1			/* v0 = (v0 & 0x7FFFFFFF) | (v1 << 31) */
	ins		$v0, $a3, 23, 8			/* v0 = (v0 & 0x8007FFFF) | (a3 << 23) */
	jr		$ra						/* return */
	nop

dtof_denormal:
	sll		$a2, $a1, 12			/* a2 = a1 << 12 */
	srl		$v0, $a2, 10			/* v0 = a2 >> 10 */
	srl		$a2, $a0, 30			/* a2 = a0 >> 30 */
	or		$v0, $v0, a2			/* v0 = v0 | a2 */
	li		$a2, 0x00400000			/* a2 = 0x00400000 */
	or		$v0, $v0, $a2			/* v0 = v0 | a2 */
	subu	$a2, $zero, $a3			/* a2 = zero - a3 */
	sltiu	$a3, $a2, 22			/* a3 = (a2 < 22) */
	beqz	$a3, dtof_min			/* if (a3==0) goto dtof_min */
	srlv	$v0, $v0, $a2			/* v0 = v0 >> a2 */
	srl		$v1, $a1, 31			/* v1 = (a1>>31) & 1 */
	ins		$v0, $v1, 31, 1			/* v0 = (v0 & 0x7FFFFFFF) | (v1 << 31) */
	jr		$ra						/* return */
	nop

dtof_zero:
	sll		$a2, $a1, 12			/* a2 = a1 << 12 */
	or		$a2, $a2, $a0			/* a2 = a2 | a0 */
dtof_min:
	li		$v0, 0x00000001			/* v0 = 0x00000001 */
	movz	$v0, $zero, $a2			/* v0 = (a2==0) ? zero : v0 */
	srl		$a2, $a1, 31			/* a2 = (a1 >> 31) & 1 */
	ins		$v0, $a2, 31, 1			/* v0 = (v0 & 0x7FFFFFFF) | ((a2<<31) & 0x80000000) */
	jr		$ra						/* return */
	nop

dtof_inf_normal:
	nor		$a2, $zero, $a1			/* a2 = ~a1 */
	sll		$a2, $a2, 12			/* a2 = a2 << 12 */
	bnez	$a2, dtof_normal		/* if (a2!=0) goto dtof_normal */
	srl		$a2, $a0, 28			/* a2 = a0 >> 28 */
	sltiu	$a2, $a2, 0xF			/* a2 = (a2 < 0xF) */
	bnez	$a2, dtof_normal2		/* if (a2!=0) goto dtof_normal */
	srl		$v1, $a1, 31			/* v1 = (a1>>31) & 1 */
	j		dtof_inf				/* goto dtof_inf */
	move	$v0, $zero				/* v0 = 0 */

dtof_naninf:
	sll		$a2, $a1, 12			/* a2 = a1 << 12 */
	or		$a3, $a2, $a0			/* a3 = a2 | a0 */
	srl		$v0, $a2, 9				/* v0 = a2 >> 9 */
	srl		$a2, $a0, 29			/* a2 = a2 >> 29 */
	or		$v0, $v0, $a2			/* v0 = v0 | a2 */
	sltiu	$a2, $v0, 1				/* a2 = (v0 < 1) */
	or		$v0, $v0, $a2			/* v0 = v0 | a2 */
	movz	$v0, $zero, $a3			/* v0 = (a3==0) ? zero : v0 */
dtof_inf:
	li		$v1, 0x7F800000			/* v1 = 0x7F800000 */
	or		$v0, $v0, $v1			/* v0 = v0 | v1 */
	srl		$v1, $a1, 31			/* v1 = (a1 >> 31) & 1 */
	ins		$v0, $v1, 31, 1			/* v0 = (v0 & 0x7FFFFFFF) | ((v1<<31) & 0x80000000) */
	jr		$ra						/* return */
	nop

#######################################################################################
/**
 * context save and print value
 * void printf_asm(u32 val);
 * input: a0
 * output: -
 * clobber: -
 * uses: -
 */
 _printf_asm:
	addiu	$sp, $sp, -144	# Push on the stack
	sd		$ra, 0($sp)
	sd		$at, 8($sp)
	sd		$v0, 16($sp)
	sd		$v1, 24($sp)
	sd		$a0, 32($sp)
	sd		$a1, 40($sp)
	sd		$a2, 48($sp)
	sd		$a3, 56($sp)
	sd		$t0, 64($sp)
	sd		$t1, 72($sp)
	sd		$t2, 80($sp)
	sd		$t3, 88($sp)
	sd		$t4, 96($sp)
	sd		$t5, 104($sp)
	sd		$t6, 112($sp)
	sd		$t7, 120($sp)
	sd		$t8, 128($sp)
	jal		output_extern
	sd		$t9, 136($sp)
	ld		$ra, 0($sp)
	ld		$at, 8($sp)
	ld		$v0, 16($sp)
	ld		$v1, 24($sp)
	ld		$a0, 32($sp)
	ld		$a1, 40($sp)
	ld		$a2, 48($sp)
	ld		$a3, 56($sp)
	ld		$t0, 64($sp)
	ld		$t1, 72($sp)
	ld		$t2, 80($sp)
	ld		$t3, 88($sp)
	ld		$t4, 96($sp)
	ld		$t5, 104($sp)
	ld		$t6, 112($sp)
	ld		$t7, 120($sp)
	ld		$t8, 128($sp)
	ld		$t9, 136($sp)
	jr		$ra			/* return */
	addiu	$sp, $sp, 144	# restore the stack

#######################################################################################
/**
 * Unsigned 64bit multiply (A * B) -> 128bit result
 * void _DMULTU(u64 A, u32 B);
 * input: a0, a1
 * output: -
 * clobber: a0, a1, a2, v0, v1
 * uses: -
 */
_DMULTU:
	pexcw	$a0, $a0
	pexcw	$a1, $a1
	pmultuw $v0, $a0, $a1
	pexew  	$a1, $a1
	pmultuw $v1, $a0, $a1
	dsrl32  $a0, $v0, 0
	daddu	$a0, $a0, $v1 		// temp2
	pexcw	$a1, $v1
	dsrl32  $a1, $a1, 0
	daddu	$a1, $a1, $a0 		// result2
	sw		$v0, _MultLo+0($fp)
	sw		$a1, _MultLo+4($fp)
	dsrl32  $a1, $a1, 0 		// (result2 >> 32)
	pcpyud	$a0, $v1, $zero 	// temp3
	dsrl32  $a0, $a0, 0 		// (temp3 >> 32)
	pcpyud	$a2, $v0, $zero		// op2 * op4
	daddu	$a0, $a2, $a0		// temp4
	daddu	$a0, $a1, $a0 		// result3
	jr		$ra
	sd		$a0, _MultHi+0($fp)

#######################################################################################
/**
 * Signed 64bit multiply (A * B) -> 128bit result
 * void _DMULT(u64 A, u64 B);
 * input: a0, a1
 * output: -
 * clobber: a0, a1, a2, a3, v0, v1
 * uses: t0
 */
_DMULT:
	pexcw	$a0, $a0
	pexcw	$a1, $a1
	pmultw  $v0, $a0, $a1
	pexew  	$a1, $a1
	pmultw  $v1, $a0, $a1
	dsrl32  $a0, $v0, 0
	daddu	$a0, $a0, $v1 		// temp2
	pexcw	$a1, $v1
	dsrl32  $a1, $a1, 0
	daddu	$a1, $a1, $a0 		// result2
	sw		$v0, _MultLo+0($fp)
	sw		$a1, _MultLo+4($fp)
	dsrl32  $a1, $a1, 0 		// (result2 >> 32)
	pcpyud	$a0, $v1, $zero 	// temp3
	dsrl32  $a0, $a0, 0 		// (temp3 >> 32)
	pcpyud	$a2, $v0, $zero		// op2 * op4
	daddu	$a0, $a2, $a0		// temp4
	daddu	$a0, $a1, $a0 		// result3
	jr		$ra
	sd		$a0, _MultHi+0($fp)

#######################################################################################
/**
 * Unsigned 64bit division (Num /Div) -> 64bit quotient and 32bit reminder 
 * void _DDIVU(u32 Num_LSB, u32 Num_MSB, u32 Div_LSB);
 * input: a0, a1, a2
 * output: -
 * clobber: a0, a1, a2, a3, v0, v1
 * uses: t0
 */
_DDIVU:
	 move 	$a2, $a1
	 dsrl32 $a1, $a0, 0
	 pextlw	$a1, $a1, $a1
     beqz	$a1, DDIVU_skip1	//Check if we need a full 64bit division
     sw		$zero,_MultHi+4($fp)	//Reminder hi

     divu	$a1,$a2
     mflo	$a3
     mfhi	$a1
     sw		$a3,_MultLo+4($fp)	//Quot hi
     sd		$t0,_Temp1($fp)	//save reg content
     move	$v0,$zero
     move	$v1,$zero
     b		DDIVU_skip2
     li		$a3,33
DDIVU_loop1:
     srl	$v1,$a1,0x1f
     sll	$a1,$a1,0x1
     or		$a1,$a1,$t0
     sll	$a0,$a0,0x1
     sll	$v0,$v0,0x1
     bnez	$v1, DDIVU_skip3
DDIVU_skip2:
     sltu	$t0,$a1,$a2

     bnez	$t0, DDIVU_skip4
DDIVU_skip3:
     addiu	$a3,$a3,-1
     subu	$a1,$a1,$a2
     addiu	$v0,$v0,1

DDIVU_skip4:
     bnez	$a3, DDIVU_loop1
     srl	$t0,$a0,0x1f

     ld		$t0,_Temp1($fp)	//restore reg content
     sw		$v0,_MultLo+0($fp)	//Quot lo
     jr		$ra
     sw		$a1,_MultHi+0($fp)	//Reminder lo

DDIVU_skip1:	//Do a 32bit div only     
     divu	$a0,$a2
     mflo	$v0
     mfhi	$a1
     sw		$v0,_MultLo+0($fp)	//Quot lo
     sw		$zero,_MultLo+4($fp)	//Quot hi
     jr		$ra
     sw		$a1,_MultHi+0($fp)	//Reminder lo
     
#######################################################################################
/**
 * Signed 64bit division (Num / Div) -> 64bit quotient and 32bit reminder 
 * void _DDIV(s64 Num, s32 Div);
 * input: a0, a1, a2
 * output: -
 * clobber: a0, a1, a2, a3, v0, v1
 * uses: t0, t1, t2
 */
_DDIV:
	move 	$a2, $a1
	dsrl32 	$a1, $a0, 0
	pextlw	$a1, $a1, $a1
	sd		$t2,_Temp3($fp)	//save reg content
     
	bgez	$a1,DDIV_skip1	//Make numerator positive if needed
	slt		$t2, $a1, $zero      //sign = value < 0 ? 1 : 0
	negu	$a0,$a0
	negu	$a1,$a1
	sltu	$v0,$zero,$a0
	subu	$a1,$a1,$v0
DDIV_skip1:
	bgez	$a2,DDIV_skip2	//Make dividend positive if needed
	sd		$t0,_Temp1($fp)	//save reg content
	xori	$t2,$t2,0x1		//sign ^= 1
 	negu	$a2,$a2
DDIV_skip2:
 	beqz	$a1,DDIV_skip8	//Check if top 32bit == 0
	sd		$t1,_Temp2($fp)	//save reg content

 	divu	$a1,$a2			//Do long 64bit division
 	move	$v0,$zero
 	move	$t0,$zero
 	li		$v1,33
 	mflo	$t1
 	b		DDIV_skip4
 	mfhi	$a3
 	
DDIV_loop1:
 	srl		$t0,$a3,0x1f
 	sll		$a3,$a3,0x1
 	or		$a3,$a3,$a1
 	sll		$a0,$a0,0x1
 	sll		$v0,$v0,0x1
 	bnez	$t0,DDIV_skip5
DDIV_skip4:
 	sltu	$a1,$a3,$a2
 	bnez	$a1,DDIV_skip6
DDIV_skip5:
 	addiu	$v1,$v1,-1
 	subu	$a3,$a3,$a2
 	addiu	$v0,$v0,1
DDIV_skip6:
 	bnez	$v1,DDIV_loop1
 	srl		$a1,$a0,0x1f
 	
DDIV_loop2:
 	beqz	$t2,DDIV_skip7	//Need sign flip on result?
	ld		$t0,_Temp1($fp)	//restore reg content

 	negu	$v0,$v0
 	negu	$t1,$t1
 	sltu	$v1,$zero,$v0
 	subu	$t1,$t1,$v1
 	negu	$a3,$a3
DDIV_skip7:	//No sign flip needed
 	sw		$v0,_MultLo+0($fp)	//Quot lo
 	sw		$t1,_MultLo+4($fp)	//Quot hi
 	sw		$a3,_MultHi+0($fp)	//Rem lo
	ld		$t1,_Temp2($fp)	//restore reg content
 	jr		$ra
	ld		$t2,_Temp3($fp)	//restore reg content

DDIV_skip8:	//Do short 32bit division 
	divu	$a0,$a2
 	move	$t1,$zero	//hi part of reminder will be zero
 	mflo	$v0
 	b		DDIV_loop2
 	mfhi	$a3
 	
#######################################################################################

	.set pop

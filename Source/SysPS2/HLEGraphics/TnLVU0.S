// Copyright (C) 2001 StrmnNrmn
// Copyright (C) 2011 Corn

#define ABI_EABI64
#include "as_reg_compat.h"

#define LIGHTSZ				6	//1<<6 bytes
#define PARAMS_FLAGS_NLIGHT_TXSCAL	0x00
#define PARAMS_LIGHTS		0x10
#define COORDMOD1		   (16 + 12 * (1<<LIGHTSZ) + 32)
#define COORDMOD2		   (16 + 12 * (1<<LIGHTSZ) + 48)
#define FOGPARAM		   (16 + 12 * (1<<LIGHTSZ) + 64)
#define LIGHTDIR			0
#define LIGHTCOL			16
#define LIGHTPOS			32
#define LIGHTSCL			48

#define	TNL_LIGHT			(1<<0)
#define	TNL_TEXGEN			(1<<1)
#define	TNL_TEXGENLIN		(1<<2)
#define	TNL_FOG				(1<<3)
#define	TNL_SHADE			(1<<4)
#define	TNL_ZBUFFER			(1<<5)
#define	TNL_TRICULL			(1<<6)
#define	TNL_CULLBACK		(1<<7)
#define	TNL_POINTLIGHT		(1<<8)

#if __GNUC__ > 3
#define VUR(x) $x
#else
#define VUR(x) x
#endif

.data
.align 4
F001:
.word	0x3f000000, 0x3e800000, 0x30000000, 0x3ec00000 //0.5 0.25 ? 0.375
	
.text
.set		push
.set		noreorder
.set		noat

############################
.global _TnLVU0
############################
#	a0 - world matrix				- must be aligned to 16 bytes
#	a1 - world*projection matrix	- must be aligned to 16 bytes
#	a2 - Fiddled vertices			- stride 16
#	a3 - Output vertices			- must be aligned to 16 bytes, stride 64
#	t0 - num vertices
#	t1 - params

# Lighting calculation
# VUR(vf1)-VUR(vf4): World Matrix
# VUR(vf5)-VUR(vf8): Projection Matrix
# VUR(vf9): Material normal 
# VUR(vf10): Accumulated colour
# VUR(vf11): ?
# VUR(vf12): ?
# VUR(vf13): ?
# VUR(vf14): Light normal
# VUR(vf15): Light colour
# VUR(vf16): Scratch
# VUR(vf17): current vertex Alpha value
# VUR(vf18): Ambient
# VUR(vf19): FogMult & FogOffs
# VUR(vf19zw): Texture X & Y scale
# VUR(vf20): Vertex position
# VUR(vf21): project transform [x,y,z,w]
# t4 = cur_light
# t6 = first_light
# t7 = last_light
# v0 = TnLFlags

_TnLVU0:
	la			$t2, F001
	lqc2		VUR(vf31), 0($t2)

	lqc2		VUR(vf1), 0($a0)				// Load mat world
	lqc2		VUR(vf2), 16($a0)
	lqc2		VUR(vf3), 32($a0)
	lqc2		VUR(vf4), 48($a0)

	lqc2		VUR(vf5), 0($a1)				// Load mat project
	lqc2		VUR(vf6), 16($a1)
	lqc2		VUR(vf7), 32($a1)
	lqc2		VUR(vf8), 48($a1)
	
	lqc2		VUR(vf19), PARAMS_FLAGS_NLIGHT_TXSCAL($t1)	// Load params [Flags, Num_lights, tscale_x, tscale_y]		
	qmfc2		$t7, VUR(vf19)								// Num_lights
	dsrl32 		$t7, $t7, 0

# Calculate the last light index
	addiu		$t6, $t1, PARAMS_LIGHTS		// pointer to first_light = p_lights
	sll			$t7, $t7, LIGHTSZ			// num_lights*64
	addu		$t7, $t6, $t7				// last_light = p_lights + num_lights*64
	lqc2		VUR(vf18), LIGHTCOL($t7)			// Load ambient color
	
	sll			$t0, $t0, 4					// count = count * 16
	addu		$t0, $a2, $t0				// end_ptr = start_ptr + count * 16
	qmfc2		$v0, VUR(vf19)					// TnL flags
	beq			$a2, $t0, finished_
	pextlw		$v0, $zero, $v0

	lw			$t2, FOGPARAM($t1)			// Load fog param [FogMult]
	lw			$t3, FOGPARAM+4($t1)		// Load fog param [FogOffs]
	pextlw		$t2, $t3, $t2

	qmtc2		$t2, VUR(vf22)
	vmove.xy	VUR(vf19), VUR(vf22)

next_vertex_:
# Load and transform this vertex position
	lw			$t2, 0($a2)					// [y,x]
	lw			$t3, 4($a2)					// [?,z]
	pextlw		$t2, $t3, $t2

	pextlh		$t2, $t2, $zero				// [y,x,?,z]
	qmtc2		$t2, VUR(vf9)
	vitof15.xyzw	VUR(vf9), VUR(vf9)				// int -> float
	vmulx.xyzw  VUR(vf9), VUR(vf9), VUR(vf31x)
		
	vmove.w		VUR(vf20), VUR(vf0)					// unfiddle and save for point lighting
	vmr32.xz	VUR(vf20), VUR(vf9)
	vaddx.y		VUR(vf20), VUR(vf0), VUR(vf9x)

	vmulax.xyzw     VUR(ACC), VUR(vf1), VUR(vf20)			// World transform
    vmadday.xyzw    VUR(ACC), VUR(vf2), VUR(vf20)
    vmaddaz.xyzw    VUR(ACC), VUR(vf3), VUR(vf20)
    vmaddw.xyzw     VUR(vf10), VUR(vf4), VUR(vf20)

	vmulax.xyzw     VUR(ACC), VUR(vf5), VUR(vf20)			// World*Projection transform
    vmadday.xyzw    VUR(ACC), VUR(vf6), VUR(vf20)
    vmaddaz.xyzw    VUR(ACC), VUR(vf7), VUR(vf20)
    vmaddw.xyzw     VUR(vf21), VUR(vf8), VUR(vf20)

	sqc2		VUR(vf10), 0x00($a3)				// Store world transform
	sqc2		VUR(vf21), 0x10($a3)				// Store projection transform
	
# Compute the clip flags
	vclipw.xyz	VUR(vf21), VUR(vf21w)
	vnop
	vnop
	vnop
	vnop
	vnop
	cfc2		$t5, $vi18
	andi		$t5, 0x3F				// Mask out the condition codes we dont care about
	qmfc2		$t2, VUR(vf21)				// Keep the condition w > 0 (used for fog)
	pcpyud		$t2, $t2, $t2
	blez		$t2, __wnegz
	move		$t3, $zero
	ori			$t3, $zero, 0x8
__wnegz:

#Light or Color?
	andi		$t4, $v0, TNL_LIGHT			// if( TNL_LIGHT )
	beqz		$t4, do_color_
	sw			$t5, 0x38($a3)				// Store ClipFlags
	
#Convert the alpha in VUR(vf9) to float and pass it along to light color
	lw			$t2, 12($a2)			// VUR(vf9x) <- load model normal or color word [w,z,y,x]/[a,b,g,r]
	pextlb		$t2, $t2, $t2
	pextlh		$t2, $t2, $t2			// [a,z,y,x]
	psrlw		$t2, $t2, 1
	qmtc2		$t2, VUR(vf12)
	vitof0.x	VUR(vf22), VUR(vf12)
	vaddx.w		VUR(vf17), VUR(vf0), VUR(vf22x)
	vmulz.w		VUR(vf17), VUR(vf17), VUR(vf31z)

#Check if there are any lights to process
	beq			$t6, $t7, done_lighting_	// cur_light == last_light?
	vmove.xyzw	VUR(vf10), VUR(vf18)					// Colour = ambient

	or			$t4, $t6, $0				// cur_light = p_lights

# Convert the model normal in VUR(vf9) to floats and transform
	lw			$t2, 12($a2)			// VUR(vf9x) <- load model normal or color word [w,z,y,x]/[a,b,g,r]
	pextlb		$t2, $t2, $zero
	pextlh		$t2, $t2, $zero			// [a,z,y,x]
	qmtc2		$t2, VUR(vf12)
	vitof0.xyzw	VUR(vf12), VUR(vf12)
	vmr32.xyzw	VUR(vf12), VUR(vf12)				// [z,y,x,a]
	vmr32.xyzw	VUR(vf22), VUR(vf12)				// [y,x,a,z]
	vmr32.xz	VUR(vf12), VUR(vf22)				// [x,y,z,a]
	vmulax.xyz  VUR(ACC), VUR(vf1), VUR(vf12)			// Transform with world matrix (only need 3x3)//Corn
    vmadday.xyz VUR(ACC), VUR(vf2), VUR(vf12)
    vmaddz.xyz  VUR(vf9), VUR(vf3), VUR(vf12)
	vmul.xyz	VUR(vf11), VUR(vf9), VUR(vf9)			// VUR(vf11x) = x*x + y*y + z*z
	vaddy.x		VUR(vf11), VUR(vf11), VUR(vf11y)
	vaddz.x		VUR(vf11), VUR(vf11), VUR(vf11z)
#if 1
	vrsqrt		VUR(Q), VUR(vf0w), VUR(vf11x)			// VUR(vf11x) = 1/sqrt(x*x + y*y + z*z)
#else
	vsqrt		VUR(Q), VUR(vf11x)
	vwaitq
	vaddq.x		VUR(vf11), VUR(vf0), VUR(Q)
	vdiv		VUR(Q), VUR(vf0w), VUR(vf11x)
#endif
	vwaitq
	vmulq.xyz   VUR(vf9), VUR(vf9), VUR(Q)			// VUR(vf9x) = v.normalise().

next_light_:
	lqc2		VUR(vf14), LIGHTDIR($t4)			// Load Light normal
	vmul.xyz	VUR(vf16), VUR(vf9), VUR(vf14)				// x = clamp(dot(normal,(x,y,z)),0,1)
	vaddy.x		VUR(vf16), VUR(vf16), VUR(vf16y)
	vaddz.x		VUR(vf16), VUR(vf16), VUR(vf16z)
	vminiw.x	VUR(vf16), VUR(vf16), VUR(vf0w)
	vmaxx.x		VUR(vf16), VUR(vf16), VUR(vf0x)
	lqc2		VUR(vf15), LIGHTCOL($t4)			// Load Light colour
	addiu		$t4, $t4, (1<<LIGHTSZ)		// Skip to the next light
	vmulx.xyz   VUR(vf16), VUR(vf15), VUR(vf16x)			// r,g,b = r*x, g*x, b*x
	bne			$t4, $t7, next_light_
	vadd.xyz	VUR(vf10), VUR(vf10), VUR(vf16)			// col += r,g,b

done_lighting_:
	vmove.xyz	VUR(vf17), VUR(vf10)					// Clamp 0..1 and merge with vertex alpha in VUR(vf17w)
	vminiw.xyz	VUR(vf17), VUR(vf17), VUR(vf0w)
	vmaxx.xyz	VUR(vf17), VUR(vf17), VUR(vf0x)

	andi		$t4, $v0, TNL_TEXGEN		// if( TNL_TEXGEN )
	beqz		$t4, do_texture_
	nop

# We use worldproject matrix to calc normals it gives a nicer effect (model view result is in VUR(vf9)) //Corn
	vmulax.xyz  VUR(ACC), VUR(vf5), VUR(vf12)			// Transform with projworld matrix, looks nicer (only need 3x3)
    vmadday.xyz VUR(ACC), VUR(vf6), VUR(vf12)
    vmaddz.xyz  VUR(vf9), VUR(vf7), VUR(vf12)
	vmul.xyz	VUR(vf10), VUR(vf9), VUR(vf9)			// VUR(vf10x) = x*x + y*y + z*z
	vaddy.x		VUR(vf10), VUR(vf10), VUR(vf10y)
	vaddz.x		VUR(vf10), VUR(vf10), VUR(vf10z)
#if 1
	vrsqrt		VUR(Q), VUR(vf0w), VUR(vf10x)					// VUR(vf10x) = 1/sqrt(x*x + y*y + z*z)
#else	
	vsqrt		VUR(Q), VUR(vf10x)
	vwaitq
	vaddq.x		VUR(vf10), VUR(vf0), VUR(Q)
	vdiv		VUR(Q), VUR(vf0w), VUR(vf10x)
#endif
	andi		$t4, $v0, TNL_TEXGENLIN		// if( TNL_TEXGENLIN )
	vwaitq
	beqz		$t4, do_texgen_
	vmulq.xy    VUR(vf9), VUR(vf9), VUR(Q)					// VUR(vf11) = v.normalise() (x & y).

# EnvMapped G_TEXTURE_GEN  t.x = 0.5 * (1.0 + n.x) t.y = 0.25 * (1.0 + n.y)
	vaddw.xy	VUR(vf9), VUR(vf9), VUR(vf0w)			// 1+x, 1+y
	vmulx.xy    VUR(vf9), VUR(vf9), VUR(vf31x)			// X * 0.5, Y * 0.25
	qmfc2		$t2, VUR(vf9)
	sw			$t2, 0x30($a3)				// Store Texture.x
	dsrl32		$t2, $t2, 0
	b			vtx_done_
	sw			$t2, 0x34($a3)				// Store Texture.y
		
do_texgen_:
# EnvMapped G_TEXTURE_GEN_LINEAR Cheap way to do acos(x)/PI -> 0.5f - 0.25f * absf(x) - 0.25f * absf(x) * absf(x) * absf(x) //Corn
	vabs.xy		VUR(vf9), VUR(vf9)					// absf(x), absf(y)
	vmuly.xy	VUR(vf23), VUR(vf9), VUR(vf31y)			// X * 0.25, Y * 0.25
	vaddx.xy	VUR(vf22), VUR(vf0), VUR(vf31x)			// result = 0.5 - X * 0.25
	vsub.xy		VUR(vf12), VUR(vf22), VUR(vf23)
	vmul.xy		VUR(vf23), VUR(vf9), VUR(vf23)			// X * X * 0.25, Y * Y * 0.25
	vmul.xy		VUR(vf23), VUR(vf9), VUR(vf23)			// X * X * X * 0.25, Y * Y * Y * 0.25
	vsub.xy		VUR(vf12), VUR(vf12), VUR(vf23)		// result -= X * X * X * 0.25
	qmfc2		$t2, VUR(vf12)
	sw			$t2, 0x30($a3)				// Store Texture.x
	dsrl32		$t2, $t2, 0
	b			vtx_done_
	sw			$t2, 0x34($a3)				// Store Texture.y
		
do_color_:
# Normalise the RGBA colour
	lw			$t2, 12($a2)			// VUR(vf9x) <- load model normal or color word [w,z,y,x]/[a,b,g,r]
	pextlb		$t2, $t2, $t2
	pextlh		$t2, $t2, $t2			// [a,b,g,r]
	psrlw		$t2, $t2, 1
	qmtc2		$t2, VUR(vf9)
	vmr32.xyzw	VUR(vf17), VUR(vf9)				// [b,g,r,a]
	vaddz.x		VUR(vf17), VUR(vf0), VUR(vf17z)		// [r,g,r,a]
	vaddy.z		VUR(vf17), VUR(vf0), VUR(vf9y)			// [r,g,b,a]	
	vitof0.xyzw	VUR(vf17), VUR(vf17)				// int -> float, VUR(vf9) = [r * 1/256, g * 1/256, b * 1/256, a * 1/256]
	vmulz.xyzw	VUR(vf17), VUR(vf17), VUR(vf31z)

do_texture_:
# Textured t.x = (float)v.tu * mTextureScale.x 	t.y = (float)v.tv * mTextureScale.y
	lw			$t2, 8($a2)				// load texture word [tv,tu] (N.B. due to swizzling these are 'backwards' from what you might expect)
	pextlh		$t2, $t2, $zero
	qmtc2		$t2, VUR(vf11)
	vitof15.xy	VUR(vf11), VUR(vf11)				// int -> float
	vmulx.xy    VUR(vf11), VUR(vf11), VUR(vf31x)
	vmulz.y		VUR(vf11), VUR(vf11), VUR(vf19z)			// multiply tu by mTextureScale.x
	vmulw.x		VUR(vf11), VUR(vf11), VUR(vf19w)			// multiply tv by mTextureScale.y			
	qmfc2		$t2, VUR(vf11)
	sw			$t2, 0x34($a3)				// Store Texture.y
	dsrl32		$t2, $t2, 0
	sw			$t2, 0x30($a3)				// Store Texture.x

vtx_done_:
	andi		$t4, $v0, TNL_FOG
	beqz		$t4, fog_done_				// if( TNL_FOG )
	nop
	beqz		$t3, fog_done_				// if( proj.w > 0.0f )
	vmr32.w		VUR(vf17), VUR(vf0)					// fog_alpha = 0.0f

#Calculate fog factor and put as alpha
	vdiv		VUR(Q), VUR(vf0w), VUR(vf21w)				// 1/w	
	vmulz.x		VUR(vf10), VUR(vf19), VUR(vf21z)			// fogmul * z			
	vwaitq
	vmulq.x		VUR(vf10), VUR(vf10), VUR(Q)				// fogmul * z * 1/w	
	vaddy.x		VUR(vf22), VUR(vf10), VUR(vf19y)			// fog_alpha = Clamp[0:1] fogmul * z * 1/w + fogoffs
	vmr32.w		VUR(vf17), VUR(vf22)
	vminiw.w	VUR(vf17), VUR(vf17), VUR(vf0w)
	vmaxx.w		VUR(vf17), VUR(vf17), VUR(vf0x)

fog_done_:
	sqc2		VUR(vf17), 0x20($a3)				// Store colour

# Continue with the next vertex
	addiu		$a2, $a2, 16				// Next input vertex
	bne			$a2, $t0, next_vertex_
	addiu		$a3, $a3, 64				// Next output vertex

finished_:	
	jr			$ra
	nop

#Used by Zelda MM
############################
.global _TnLVU0_Plight
############################
#	a0 - world matrix				- must be aligned to 16 bytes
#	a1 - world*projection matrix	- must be aligned to 16 bytes
#	a2 - Fiddled vertices			- stride 16
#	a3 - Output vertices			- must be aligned to 16 bytes, stride 64
#	t0 - num vertices
#	t1 - params

# Lighting calculation
# M000: World Matrix
# M100: Projection Matrix
# VUR(vf9): Material normal 
# VUR(vf10): Accumulated colour
# VUR(vf11): ?
# VUR(vf12): ?
# VUR(vf13): ?
# VUR(vf14): Scratch
# VUR(vf15): Scratch
# VUR(vf16): Scratch
# VUR(vf17): current vertex Alpha value
# VUR(vf18): Ambient
# VUR(vf19): FogMult & FogOffs
# VUR(vf19zw): Texture X & Y scale
# VUR(vf20): Vertex position
# VUR(vf21): project transform [x,y,z,w]
# t4 = cur_light
# t6 = first_light
# t7 = last_light
# v0 = TnLFlags

_TnLVU0_Plight:
	lqc2		VUR(vf1), 0($a0)				// Load mat world
	lqc2		VUR(vf2), 16($a0)
	lqc2		VUR(vf3), 32($a0)
	lqc2		VUR(vf4), 48($a0)

	lqc2		VUR(vf5), 0($a1)				// Load mat project
	lqc2		VUR(vf6), 16($a1)
	lqc2		VUR(vf7), 32($a1)
	lqc2		VUR(vf8), 48($a1)
	
	lqc2		VUR(vf19), PARAMS_FLAGS_NLIGHT_TXSCAL($t1)	// Load params [Flags, Num_lights, tscale_x, tscale_y]
	#vmov.p		VUR(vf19zw), VUR(vf19zw)[y,x]				// Swizzle texture X&Y scale 
	vmr32.y		VUR(vf22), VUR(vf19)						// [?, tscale_x, ?, ?]
	vmr32.x		VUR(vf22), VUR(vf22)						// [tscale_x, ?, ?, ?]
	vmr32.z		VUR(vf19), VUR(vf19)						// [?, ?, tscale_y, ?]
	vmr32.w		VUR(vf19), VUR(vf22)						// [?, ?, tscale_y, tscale_x]

	#mfv			$t7, VUR(vf19y)					// Num_lights
	#mfv			$v0, VUR(vf19x)					// TnL Flags
	qmfc2		$t7, VUR(vf19)
	move		$v0, $t7
	dsrl32 		$t7, $t7, 0

	#lv.s		VUR(vf19x), FOGPARAM($t1)		// Load fog param [FogMult]
	#lv.s		VUR(vf19y), FOGPARAM+4($t1)		// Load fog param [FogOffs]
	ld			$t2, FOGPARAM($t1)
	qmtc2		$t2, VUR(vf22)
	vmove.xy	VUR(vf19), VUR(vf22)
		
# Calculate the last light index
	addiu		$t6, $t1, PARAMS_LIGHTS		// pointer to first_light = p_lights
	sll			$t7, $t7, LIGHTSZ			// num_lights*64
	addu		$t7, $t6, $t7				// last_light = p_lights + num_lights*64
	
	sll			$t0, $t0, 4					// count = count * 16
	addu		$t0, $a2, $t0				// end_ptr = start_ptr + count * 16
	beq			$a2, $t0, finished_Plight
	lqc2		VUR(vf18), LIGHTCOL($t7)			// Load ambient color
	
next_vertex_Plight:
# Load and transform this vertex position
 	#lv.s		VUR(vf9x), 0($a2)				// load word [y,x,?,z]
 	#lv.s		VUR(vf9y), 4($a2)				// ulqc2 is buggy on PHAT
	#vs2i.p		VUR(vf9), VUR(vf9)					// VUR(vf9) = [?,z,y,x]
	ld			$t2, 0($a2)					// [y,x,?,z]
	pextlh		$t2, $t2, $zero
	qmtc2		$t2, VUR(vf22)
	vmove.xyzw	VUR(vf9), VUR(vf22)
	#vi2f.q		VUR(vf9), VUR(vf9), 16				// int -> float
	vitof15.xyzw	VUR(vf9), VUR(vf9)
	lui			$t2, 0x3f00				// 0.5
	qmtc2		$t2, VUR(vf22)
	vmulx.xyzw  VUR(vf9), VUR(vf9), VUR(vf22x)
	#vmov.q		VUR(vf20), VUR(vf9)[y,x,w,1]			// unfiddle and save for point lighting
	vmove.w		VUR(vf20), VUR(vf0)
	vmr32.xz	VUR(vf20), VUR(vf9)
	vaddx.y		VUR(vf20), VUR(vf0), VUR(vf9x)
	#vtfm4.q		VUR(vf10), M000, VUR(vf20)			// World transform
	vmulax.xyzw     VUR(ACC), VUR(vf1), VUR(vf20)
    vmadday.xyzw    VUR(ACC), VUR(vf2), VUR(vf20)
    vmaddaz.xyzw    VUR(ACC), VUR(vf3), VUR(vf20)
    vmaddw.xyzw     VUR(vf10), VUR(vf4), VUR(vf20)
	#vtfm4.q		VUR(vf21), M100, VUR(vf20)			// World*Projection transform
	vmulax.xyzw     VUR(ACC), VUR(vf5), VUR(vf20)
    vmadday.xyzw    VUR(ACC), VUR(vf6), VUR(vf20)
    vmaddaz.xyzw    VUR(ACC), VUR(vf7), VUR(vf20)
    vmaddw.xyzw     VUR(vf21), VUR(vf8), VUR(vf20)
	sqc2		VUR(vf10), 0x00($a3)				// Store world transform
	sqc2		VUR(vf21), 0x10($a3)				// Store projection transform
	
# Compute the clip flags
	#vcmp.q		LT, VUR(vf21), VUR(vf21)[-w,-w,-w,0]	// x < -w, y < -w, z < -w
	vclipw.xyz	VUR(vf21), VUR(vf21w)
	#lv.s		VUR(vf9x), 12($a2)				// VUR(vf9x) <- load model normal or color word [w,z,y,x]/[a,b,g,r]
	#mfvc		$t4, $131					// VU0_CC. Corresponds to X_NEG/Y_NEG/Z_NEG (will become X_POS/Y_POS/Z_POS later)
	#vcmp.q		GT, VUR(vf21), VUR(vf21)[w,w,w,0]		// x > w, y > w, z > w, w > 0
	#andi		$t4, $t4, 0x7				// Mask out the condition codes we dont care about
	#sll			$t4, $t4, 3					// Shift up to create X_POS/Y_POS/Z_POS	
	#mfvc		$t5, $131					// VU0_CC. Corresponds to X_NEG/Y_NEG/Z_NEG
	#andi		$t3, $t5, 0x8				// Keep the condition w > 0 (used for fog)
	#andi		$t5, $t5, 0x7				// Mask out the condition codes we dont care about
	#or			$t5, $t4, $t5
	vnop
	vnop
	vnop
	vnop
	vnop
	cfc2		$t5, $vi18
	andi		$t5, 0x3F
	sw			$t5, 0x38($a3)				// Store ClipFlags
	qmfc2		$t2, VUR(vf21)
	pcpyud		$t2, $t2, $t2
	blez		$t2, __wnegz_Plight
	move		$t3, $zero
	ori			$t3, $zero, 0x8
__wnegz_Plight:

#Convert the alpha in VUR(vf9) to float and pass it along to light color
	#.word		0xd0380000 | (8<<8) | (43)	// vuc2i.s	VUR(vf12), VUR(vf9x)					// VUR(vf9) = [a,z,y,x]
	#vi2f.s		VUR(vf17w), VUR(vf12x), 31				// int -> float, VUR(vf17) = [a * 1/256]
	lw			$t2, 12($a2)
	pextlb		$t2, $t2, $t2
	pextlh		$t2, $t2, $t2			// [a,z,y,x]
	psrlw		$t2, $t2, 1
	qmtc2		$t2, VUR(vf12)
	vitof0.x	VUR(vf22), VUR(vf12)
	vmr32.w		VUR(vf17), VUR(vf22)
	lui			$t2, 0x3000
	qmtc2		$t2, VUR(vf22)
	vmulx.w		VUR(vf17), VUR(vf17), VUR(vf22x)

#Check if there are any lights to process
	beq			$t6, $t7, done_Plight		// cur_light == last_light?
	vmove.xyzw	VUR(vf10), VUR(vf18)					// Colour = ambient

	or			$t4, $t6, $0				// cur_light = p_lights

next_light_Plight:
	lqc2		VUR(vf14), LIGHTPOS($t4)			// Load Light position
	vsub.xyz	VUR(vf14), VUR(vf14), VUR(vf20)			// light pos - vertex pos
	#vdot.t		VUR(vf14z), VUR(vf14), VUR(vf14)			// VUR(vf14z) (qlen) = x*x + y*y + z*z
	vmul.xyz	VUR(vf22), VUR(vf9), VUR(vf14)
	vaddx.z		VUR(vf14), VUR(vf22), VUR(vf22x)
	vaddy.z		VUR(vf14), VUR(vf14), VUR(vf22y)
	lqc2		VUR(vf15), LIGHTSCL($t4)			// Load Light scaleing
	#vsqrt.s	VUR(vf14y), VUR(vf14z)				// VUR(vf14y) (llen) = SQRT(x*x + y*y + z*z)
	vrsqrt		VUR(Q), VUR(vf0w), VUR(vf14z)
	vwaitq
	vaddq.y		VUR(vf14), VUR(vf0), VUR(Q)
	lqc2		VUR(vf16), LIGHTCOL($t4)			// Load Light colour
	#vdot.t		VUR(vf15x), VUR(vf15), VUR(vf14)[1,y,z]	// VUR(vf15x) (L) = (1.0f*ca + llen*la + qlen*qa)
	vmul.yz		VUR(vf22), VUR(vf15), VUR(vf14)
	vaddy.x		VUR(vf15), VUR(vf15), VUR(vf22y)
	vaddz.x		VUR(vf15), VUR(vf15), VUR(vf22z)
	#mfv		$t5, VUR(vf15x)					// VUR(vf15x) (L) -> t5
	qmfc2		$t5, VUR(vf15)
	pextlw		$t5, $t5, $t5
	beqz		$t5, skip_Plight			// Skip this light if L == 0.0f (0x00000000)
	addiu		$t4, $t4, (1<<LIGHTSZ)		// Advance pointer to the next light
	#vrcp.s		VUR(vf15x), VUR(vf15x)				// VUR(vf15x) (i) = 1.0f / L
	vdiv		VUR(Q), VUR(vf0w), VUR(vf15x)
	vwaitq
	#vscl.t		VUR(vf16), VUR(vf16), VUR(vf15x)			// r,g,b = r*i, g*i, b*i
	vmulq.xyz	VUR(vf16), VUR(vf16), VUR(Q)
	#vadd.t		VUR(vf10), VUR(vf10), VUR(vf16)			// col += r,g,b
	vadd.xyz	VUR(vf10), VUR(vf10), VUR(vf16)
skip_Plight:
	bne			$t4, $t7, next_light_Plight
	nop
	
done_Plight:
	#vmov.t		VUR(vf17)[0:1,0:1,0:1], VUR(vf10)		// Clamp 0..1 and merge with vertex alpha in VUR(vf17w)
	vmove.xyz	VUR(vf17), VUR(vf10)
	vminiw.xyz	VUR(vf17), VUR(vf17), VUR(vf0w)
	vmaxx.xyz	VUR(vf17), VUR(vf17), VUR(vf0x)

# Textured t.x = (float)v.tu * mTextureScale.x 	t.y = (float)v.tv * mTextureScale.y
	#lv.s		VUR(vf11x), 8($a2)				// load texture word [tv,tu] (N.B. due to swizzling these are 'backwards' from what you might expect)
	#vs2i.s		VUR(vf11), VUR(vf11x)
	lw			$t2, 8($a2)
	pextlh		$t2, $t2, $zero
	qmtc2		$t2, VUR(vf11)
	#vi2f.p		VUR(vf11), VUR(vf11), 16				// int -> float
	vitof15.xy	VUR(vf11), VUR(vf11)
	lui			$t2, 0x3f00				// 0.5
	qmtc2		$t2, VUR(vf22)
	vmulx.xy    VUR(vf11), VUR(vf11), VUR(vf22x)
	#vmul.p		VUR(vf11), VUR(vf11), VUR(vf19zw)			// multiply by mTextureScale
	vmulz.y		VUR(vf11), VUR(vf11), VUR(vf19z)
	vmulw.x		VUR(vf11), VUR(vf11), VUR(vf19w)
	#sv.s		VUR(vf11y), 0x30($a3)				// Store Texture.x
	qmfc2		$t2, VUR(vf11)
	sw			$t2, 0x34($a3)
	dsrl32		$t2, $t2, 0
	andi		$t4, $v0, TNL_FOG
	beqz		$t4, fog_done_plight		// if( TNL_FOG )
	#sv.s		VUR(vf11x), 0x34($a3)				// Store Texture.y
	sw			$t2, 0x30($a3)
	beqz		$t3, fog_done_plight		// if( proj.w > 0.0f )
	#vzero.s	VUR(vf17w)						// fog_alpha = 0.0f
	vmr32.w		VUR(vf17), VUR(vf0)

#Calculate fog factor and put as alpha
	#vrcp.s		VUR(vf9x), VUR(vf21w)					// 1/w
	vdiv		VUR(Q), VUR(vf0w), VUR(vf21w)
	vwaitq
	#vmul.s		VUR(vf10x), VUR(vf21z), VUR(vf19x)			// fogmul * z
	vmulz.x		VUR(vf10), VUR(vf19), VUR(vf21z)
	#vmul.s		VUR(vf10x), VUR(vf10x), VUR(vf9x)			// fogmul * z * 1/w
	vmulq.x		VUR(vf10), VUR(vf10), VUR(Q)
	#vadd.s		VUR(vf17w)[0:1], VUR(vf10x), VUR(vf19y)		// fog_alpha = Clamp[0:1] fogmul * z * 1/w + fogoffs
	vaddy.x		VUR(vf22), VUR(vf10), VUR(vf19y)
	vmr32.w		VUR(vf17), VUR(vf22)
	vminiw.w	VUR(vf17), VUR(vf17), VUR(vf0w)
	vmaxx.w		VUR(vf17), VUR(vf17), VUR(vf0x)

fog_done_plight:
	sqc2		VUR(vf17), 0x20($a3)				// Store colour

# Continue with the next vertex
	addiu		$a2, $a2, 16				// Next input vertex
	bne			$a2, $t0, next_vertex_Plight
	addiu		$a3, $a3, 64				// Next output vertex

finished_Plight:	
	jr			$ra
	nop

############################
.global _TnLVU0CBFD
############################
#	a0 - world matrix				- must be aligned to 16 bytes
#	a1 - world*projection matrix	- must be aligned to 16 bytes
#	a2 - Fiddled vertices			- stride 16
#	a3 - Output vertices			- must be aligned to 16 bytes, stride 64
#	t0 - num vertices
#	t1 - params
#	t2 - model normal pointer
#	t3 - v0

# Lighting calculation
# M000: World Matrix
# M100: Projection Matrix
# VUR(vf9): Material normal 
# VUR(vf10): Light position 
# VUR(vf11): projected
# VUR(vf12): store raw material normal
# VUR(vf13): color result
# VUR(vf14): Light direction
# VUR(vf15): Light color
# VUR(vf16): Scratch
# VUR(vf24): Accumulated colour
# VUR(vf18): Ambient light color
# VUR(vf19zw): Texture X & Y scale
# VUR(vf20): Coord [8, 9, 10, 11]
# VUR(vf21): Coord [12, 13, 14, 15]
# v0 = TnLFlags
# t4 = cur_light
# t5 = last_light(point light)
# t6 = first_light
# t7 = last_light

_TnLVU0CBFD:
	lqc2		VUR(vf1), 0($a0)				// Load mat world
	lqc2		VUR(vf2), 16($a0)
	lqc2		VUR(vf3), 32($a0)
	lqc2		VUR(vf4), 48($a0)

	lqc2		VUR(vf5), 0($a1)				// Load mat project
	lqc2		VUR(vf6), 16($a1)
	lqc2		VUR(vf7), 32($a1)
	lqc2		VUR(vf8), 48($a1)
	
	lqc2		VUR(vf19), PARAMS_FLAGS_NLIGHT_TXSCAL($t1)	// Load params [Flags, Num_lights, tscale_x, tscale_y]
	#vmov.p		VUR(vf19zw), VUR(vf19zw)[y,x]				// Swizzle texture X&Y scale 
	vmr32.y		VUR(vf22), VUR(vf19)						// [?, tscale_x, ?, ?]
	vmr32.x		VUR(vf22), VUR(vf22)						// [tscale_x, ?, ?, ?]
	vmr32.z		VUR(vf19), VUR(vf19)						// [?, ?, tscale_y, ?]
	vmr32.w		VUR(vf19), VUR(vf22)						// [?, ?, tscale_y, tscale_x]
	#mfv		$t7, VUR(vf19y)					// Num_lights
	qmfc2		$t7, VUR(vf19)
	dsrl32 		$t7, $t7, 0
	
# Load Coord Mod vectors
	lqc2		VUR(vf20), COORDMOD1($t1)		// Load Coord [8, 9, 10, 11]
	lqc2		VUR(vf21), COORDMOD2($t1)		// Load Coord [12, 13, 14, 15]

# Calculate the last light index
	addiu		$t6, $t1, PARAMS_LIGHTS		// pointer to first_light = p_lights
	sll			$t7, $t7, LIGHTSZ			// num_lights*64
	addu		$t7, $t6, $t7				// last_light = p_lights + num_lights*64
	lqc2		VUR(vf18), LIGHTCOL($t7)			// Load ambient color

# Calculate the last vertex index
	sll			$t0, $t0, 4					// count = count * 16
	addu		$t0, $a2, $t0				// end_ptr = start_ptr + count * 16
	beq			$a2, $t0, finished_CBFD
	#mfv		$v0, VUR(vf19x)					// TnL flags
	qmfc2		$v0, VUR(vf19)
	
next_vertex_CBFD:
# Load and transform this vertex position
 	#lv.s		VUR(vf9x), 0($a2)				// load word [y,x,?,z]
 	#lv.s		VUR(vf9y), 4($a2)				// ulqc2 is buggy on PHAT
	#vs2i.p		VUR(vf9), VUR(vf9)					// VUR(vf9) = [?,z,y,x]
	ld			$v1, 0($a2)					// [y,x,?,z]
	pextlh		$v1, $v1, $zero
	qmtc2		$v1, VUR(vf9)
	#vi2f.q		VUR(vf9), VUR(vf9), 16				// int -> float
	vitof15.xyzw	VUR(vf9), VUR(vf9)
	lui			$v1, 0x3f00				// 0.5
	qmtc2		$v1, VUR(vf22)
	vmulx.xyzw  VUR(vf9), VUR(vf9), VUR(vf22x)
	#vmov.q		VUR(vf12), VUR(vf9)[y,x,w,1]			// unswizzle order
	vmove.w		VUR(vf12), VUR(vf0)
	vmr32.xz	VUR(vf12), VUR(vf9)
	vaddx.y		VUR(vf12), VUR(vf0), VUR(vf9x)
	#vtfm4.q		VUR(vf10), M000, VUR(vf12)			// World transform
	vmulax.xyzw     VUR(ACC), VUR(vf1), VUR(vf12)
    vmadday.xyzw    VUR(ACC), VUR(vf2), VUR(vf12)
    vmaddaz.xyzw    VUR(ACC), VUR(vf3), VUR(vf12)
    vmaddw.xyzw     VUR(vf10), VUR(vf4), VUR(vf12)

#Load & Normalise the vertex RGBA colour
	#lv.s		VUR(vf9x), 12($a2)				// load normal word [w,z,y,x]
	#.word		0xd0380000 | (8<<8) | (40)	// vuc2i.s	VUR(vf9), VUR(vf9x)					// VUR(vf9) = [a,b,g,r]
	lw			$v1, 12($a2)
	pextlb		$v1, $v1, $v1
	pextlh		$v1, $v1, $v1			// [a,b,g,r]
	psrlw		$v1, $v1, 1
	qmtc2		$v1, VUR(vf9)
	vmr32.xyzw	VUR(vf24), VUR(vf9)				// [b,g,r,a]
	vaddz.x		VUR(vf24), VUR(vf0), VUR(vf24z)		// [r,g,r,a]
	vaddy.z		VUR(vf24), VUR(vf0), VUR(vf9y)			// [r,g,b,a]
	#vi2f.q		VUR(vf24), VUR(vf9)[w,z,y,x], 31		// int -> float, R403 = [r * 1/256, g * 1/256, b * 1/256, a * 1/256]
	lui			$v1, 0x3000
	qmtc2		$v1, VUR(vf22)
	vmulx.xyzw	VUR(vf24), VUR(vf24), VUR(vf22x)
	#vtfm4.q		VUR(vf11), M100, VUR(vf10)			// Projection transform
	vmulax.xyzw     VUR(ACC), VUR(vf5), VUR(vf10)
    vmadday.xyzw    VUR(ACC), VUR(vf6), VUR(vf10)
    vmaddaz.xyzw    VUR(ACC), VUR(vf7), VUR(vf10)
    vmaddw.xyzw     VUR(vf11), VUR(vf8), VUR(vf10)
	sqc2		VUR(vf10), 0x00($a3)				// Store world transform
	sqc2		VUR(vf11), 0x10($a3)				// Store projection transform
	
# Compute the clip flags
	#vcmp.q		LT, VUR(vf11), VUR(vf11)[-w,-w,-w,0]	// x < -w, y < -w, z < -w
	#vnop
	#mfvc		$t4, $131					// VU0_CC. Corresponds to X_NEG/Y_NEG/Z_NEG (will become X_POS/Y_POS/Z_POS later)
	#vcmp.q		GT, VUR(vf11), VUR(vf11)[w,w,w,0]		// x > w, y > w, z > w
	#andi		$t4, $t4, 0x7				// Mask out the condition codes we dont care about
	#sll		$t4, $t4, 3					// Shift up to create X_POS/Y_POS/Z_POS	
	#mfvc		$t5, $131					// VU0_CC. Corresponds to X_NEG/Y_NEG/Z_NEG
	#andi		$t5, $t5, 0x7				// Mask out the condition codes we dont care about
	#or			$t5, $t4, $t5
	vclipw.xyz	VUR(vf11), VUR(vf11w)
	vnop
	vnop
	vnop
	vnop
	vnop
	cfc2		$t5, $vi18
	andi		$t5, 0x3F

#LIGHT
	andi		$t4, $v0, TNL_LIGHT			// if( TNL_LIGHT )
	beqz		$t4, do_texture_CBFD
	sw			$t5, 0x38($a3)				// Store ClipFlags

#skip to normal light and avoid the model normal transform if only TNL_LIGHT is set
	andi		$t4, $v0, (TNL_POINTLIGHT | TNL_TEXGEN)			// if( TNL_POINTLIGHT | TNL_TEXGEN )
	beqz		$t4, do_normallight_CBFD
	nop
	
#Use world matrix to transform model normal
 	xori		$t5, $t3, 0x3				// = v0 ^ 3
	addu		$t5, $t2, $t5				// += base address
	lb			$t4, 0($t5)					// get normal x
	#mtv		$t4, VUR(vf12x)					// Store vertice normal X 
	addiu		$t5, $t3, 0x1				// = v0 + 1
 	xori		$t5, $t5, 0x3				// ^= 3
	addu		$t5, $t2, $t5				// += base address
	lb			$v1, 4($a2)					// Get vert_norm z
	pextlw		$t4, $v1, $t4
	lb			$v1, 0($t5)					// get normal y
	#mtv		$t4, VUR(vf12y)					// Store vertice normal Y 
	#mtv		$v1, VUR(vf12z)					// Store vertice normal Z 
	pextlw		$v1, $v1, $t4
	qmtc2		$v1, VUR(vf12)
	#vi2f.t		VUR(vf12), VUR(vf12), 0				// int -> float
	vitof0.xyz	VUR(vf12), VUR(vf12)
	#vtfm3.t	VUR(vf9), M000, VUR(vf12)			// Transform with world matrix, (only need 3x3)
	vmulax.xyz  VUR(ACC), VUR(vf1), VUR(vf12)
    vmadday.xyz VUR(ACC), VUR(vf2), VUR(vf12)
    vmaddz.xyz  VUR(vf9), VUR(vf3), VUR(vf12)
	#vdot.t		VUR(vf10x), VUR(vf9), VUR(vf9)			// VUR(vf10x) = x*x + y*y + z*z
	vmul.xyz	VUR(vf10), VUR(vf9), VUR(vf9)
	vaddy.x		VUR(vf10), VUR(vf10), VUR(vf10y)
	vaddz.x		VUR(vf10), VUR(vf10), VUR(vf10z)
	#vrsq.s		VUR(vf10x), VUR(vf10x)					// VUR(vf10x) = 1/sqrt(x*x + y*y + z*z)
	vrsqrt		VUR(Q), VUR(vf0w), VUR(vf10x)
	vwaitq

	andi		$t4, $v0, TNL_POINTLIGHT	// if( TNL_POINTLIGHT )
	beqz		$t4, do_normallight_CBFD
	#vscl.t		VUR(vf9), VUR(vf9), VUR(vf10x)			// VUR(vf9) = normalise transformed model vector (x, y, z).
	vmulq.xyz   VUR(vf9), VUR(vf9), VUR(Q)

#POINT LIGHT
	beq			$t6, $t7, done_plight_CBFD	// cur_light == last_light?
	#vmov.q		VUR(vf13), VUR(vf18)					// Colour = ambient
	vmove.xyzw	VUR(vf13), VUR(vf18)

	addiu		$t5, $t7, -(1<<LIGHTSZ)		// Do one light less with point light
	beq			$t6, $t5, do_dot_plight_CBFD	// cur_light == last_light?
	or			$t4, $t6, $0				// cur_light = p_lights

	#vadd.q		VUR(vf11), VUR(vf11), VUR(vf20)			// Proj + Coord1
	vadd.xyzw	VUR(vf11), VUR(vf11), VUR(vf20)
	#vmul.q		VUR(vf11), VUR(vf11), VUR(vf21)			// * Coord2
	vmul.xyzw	VUR(vf11), VUR(vf11), VUR(vf21)

next_plight_CBFD:
	lqc2		VUR(vf14), LIGHTDIR($t4)			// Load Light direction	& SkipIfZero
	#mfv		$t8, VUR(vf14w)					// SkipIfZero
	qmfc2		$t8, VUR(vf14)
	pcpyud		$t8, $t8, $t8
	dsrl32		$t8, $t8, 0
	beqz		$t8, skip_plight_CBFD
	nop
	
	lqc2		VUR(vf10), LIGHTPOS($t4)			// Load Light position
	#vsub.q		VUR(vf10), VUR(vf11), VUR(vf10)			// ProjCoord - light position
	#vdot.q		VUR(vf10x), VUR(vf10), VUR(vf10)			// VUR(vf10x) = x*x + y*y + z*z
	vsub.xyzw	VUR(vf10), VUR(vf11), VUR(vf10)
	vmul.xyzw	VUR(vf10), VUR(vf10), VUR(vf10)
	vaddy.x		VUR(vf10), VUR(vf10), VUR(vf10y)
	vaddz.x		VUR(vf10), VUR(vf10), VUR(vf10z)
	vaddw.x		VUR(vf10), VUR(vf10), VUR(vf10w)
	lqc2		VUR(vf15), LIGHTCOL($t4)			// Load Light colour & scale
	#vrcp.s		VUR(vf10x), VUR(vf10x)				// VUR(vf10x) = 1/(x*x + y*y + z*z)
	vdiv		VUR(Q), VUR(vf0w), VUR(vf10w)
	vwaitq
	#vmul.s		VUR(vf15w)[0:1], VUR(vf15w), VUR(vf10x)	// R332 = p_i clamped 0:1.
	vmulq.w		VUR(vf15), VUR(vf15), VUR(Q)
	vminiw.w	VUR(vf15), VUR(vf15), VUR(vf0w)
	vmaxx.w		VUR(vf15), VUR(vf15), VUR(vf0x)
	#vdot.t		VUR(vf16x)[0:1], VUR(vf9), VUR(vf14)		// intensity = clamp(dot(normal,(x,y,z)),0,1)
	vmul.xyz	VUR(vf16), VUR(vf9), VUR(vf14)
	vaddy.x		VUR(vf16), VUR(vf16), VUR(vf16y)
	vaddz.x		VUR(vf16), VUR(vf16), VUR(vf16z)
	vminiw.x	VUR(vf16), VUR(vf16), VUR(vf0w)
	vmaxx.x		VUR(vf16), VUR(vf16), VUR(vf0x)
	#vmul.s		VUR(vf16x), VUR(vf16x), VUR(vf15w)			// intensity *= p_i
	vmulw.x		VUR(vf16), VUR(vf16), VUR(vf15w)
	#vscl.t		VUR(vf15), VUR(vf15), VUR(vf16x)			// r,g,b = r*i, g*i, b*i
	vmulx.xyz	VUR(vf15), VUR(vf15), VUR(vf16x)
	#vadd.t		VUR(vf13), VUR(vf13), VUR(vf15)			// col += r,g,b
	vadd.xyz	VUR(vf13), VUR(vf13), VUR(vf15)

skip_plight_CBFD:
	addiu		$t4, $t4, (1<<LIGHTSZ)		// Skip to the next light
	bne			$t4, $t5, next_plight_CBFD
	nop
	
do_dot_plight_CBFD:
	lqc2		VUR(vf14), LIGHTDIR($t4)			// Load Light normal
	#vdot.t		VUR(vf16x)[0:1], VUR(vf9), VUR(vf14)		// intensity = clamp(dot(normal,(x,y,z)),0,1)
	vmul.xyz	VUR(vf16), VUR(vf9), VUR(vf14)
	vaddy.x		VUR(vf16), VUR(vf16), VUR(vf16y)
	vaddz.x		VUR(vf16), VUR(vf16), VUR(vf16z)
	vminiw.x	VUR(vf16), VUR(vf16), VUR(vf0w)
	vmaxx.x		VUR(vf16), VUR(vf16), VUR(vf0x)
	lqc2		VUR(vf15), LIGHTCOL($t4)			// Load Light colour & scale
	#vscl.t		VUR(vf15), VUR(vf15), VUR(vf16x)			// r,g,b = r*i, g*i, b*i
	vmulx.xyz	VUR(vf15), VUR(vf15), VUR(vf16x)
	#vadd.t		VUR(vf13)[0:1,0:1,0:1], VUR(vf13), VUR(vf15)	// col += r,g,b (and clamp result)
	vadd.xyz	VUR(vf13), VUR(vf13), VUR(vf15)
	vminiw.xyz	VUR(vf13), VUR(vf13), VUR(vf0w)
	vmaxx.xyz	VUR(vf13), VUR(vf13), VUR(vf0x)

done_plight_CBFD:
	b			skip_to_envmap_CBFD
	#vmul.t		VUR(vf24), VUR(vf24), VUR(vf13)			// Col *= col and merge with vertex alpha
	vmul.xyz	VUR(vf24), VUR(vf24), VUR(vf13)
	
#NORMAL LIGHT
do_normallight_CBFD:
	beq			$t6, $t7, done_nlight_CBFD	// cur_light == last_light?
	#vmov.q		VUR(vf13), VUR(vf18)					// Colour = ambient
	vmove.xyzw	VUR(vf13), VUR(vf18)

	or			$t4, $t6, $0				// cur_light = p_lights
	#vadd.q		VUR(vf11), VUR(vf11), VUR(vf20)			// Proj + Coord1
	vadd.xyzw	VUR(vf11), VUR(vf11), VUR(vf20)
	#vmul.q		VUR(vf11), VUR(vf11), VUR(vf21)			// * Coord2
	vmul.xyzw	VUR(vf11), VUR(vf11), VUR(vf21)

next_nlight_CBFD:
	lqc2		VUR(vf10), LIGHTPOS($t4)			// Load Light position
	#vsub.q		VUR(vf10), VUR(vf11), VUR(vf10)			// ProjCoord - light position
	vsub.xyzw	VUR(vf10), VUR(vf11), VUR(vf10)
	#vdot.q		VUR(vf10x), VUR(vf10), VUR(vf10)			// VUR(vf10x) = x*x + y*y + z*z
	vmul.xyzw	VUR(vf10), VUR(vf10), VUR(vf10)
	vaddy.x		VUR(vf10), VUR(vf10), VUR(vf10y)
	vaddz.x		VUR(vf10), VUR(vf10), VUR(vf10z)
	vaddw.x		VUR(vf10), VUR(vf10), VUR(vf10w)
	lqc2		VUR(vf15), LIGHTCOL($t4)			// Load Light colour & scale
	#vrcp.s		VUR(vf10x), VUR(vf10x)					// VUR(vf10x) = 1/(x*x + y*y + z*z)
	vdiv		VUR(Q), VUR(vf0w), VUR(vf10x)
	vwaitq
	#vmul.s		VUR(vf15w)[0:1], VUR(vf15w), VUR(vf10x)		// R332 = p_i clamped 0:1.
	vmulq.w		VUR(vf15), VUR(vf15), VUR(Q)
	vminiw.w	VUR(vf15), VUR(vf15), VUR(vf0w)
	vmaxx.w		VUR(vf15), VUR(vf15), VUR(vf0x)
	addiu		$t4, $t4, (1<<LIGHTSZ)		// Skip to the next light
	#vscl.t		VUR(vf15), VUR(vf15), VUR(vf15w)			// r,g,b = r*i, g*i, b*i
	vmulw.xyz	VUR(vf15), VUR(vf15), VUR(vf15w)
	bne			$t4, $t7, next_nlight_CBFD
	#vadd.t		VUR(vf13), VUR(vf13), VUR(vf15)			// col += r,g,b
	vadd.xyz	VUR(vf13), VUR(vf13), VUR(vf15)

	#vmov.t		VUR(vf13)[0:1,0:1,0:1], VUR(vf13)
	vminiw.xyz	VUR(vf13), VUR(vf13), VUR(vf0w)
	vmaxx.xyz	VUR(vf13), VUR(vf13), VUR(vf0x)

done_nlight_CBFD:
	#vmul.t		VUR(vf24), VUR(vf24), VUR(vf13)			// Col *= col and merge with vertex alpha
	vmul.xyz	VUR(vf24), VUR(vf24), VUR(vf13)

#Check environment mapping
skip_to_envmap_CBFD:
	andi		$t4, $v0, TNL_TEXGEN		// if( TNL_TEXGEN )
	beqz		$t4, do_texture_CBFD
	nop
	
	andi		$t4, $v0, TNL_TEXGENLIN		// if( TNL_TEXGENLIN )
	beqz		$t4, do_texgen_CBFD
	nop
	
# EnvMapped G_TEXTURE_GEN_LINEAR Cheap way to do acos(x)/PI -> 0.5f - 0.25f * x - 0.25f * x * x * x //Corn
	#vmul.p		VUR(vf23), VUR(vf9)[1/4,1/4], VUR(vf9)	// X * 0.25, Y * 0.25
	lui			$v1, 0x3e80				// 0.25
	qmtc2		$v1, VUR(vf22)
	vmulx.xy	VUR(vf23), VUR(vf9), VUR(vf22x)
	#vsub.p		VUR(vf10), VUR(vf9)[1/2,1/2], VUR(vf23)	// result = 0.5 - X * 0.25
	lui			$v1, 0x3f00				// 0.5
	pextlw		$v1, $v1, $v1
	qmtc2		$v1, VUR(vf22)
	vsub.xy		VUR(vf10), VUR(vf22), VUR(vf23)
	#vmul.p		VUR(vf23), VUR(vf9), VUR(vf23)			// X * X * 0.25, Y * Y * 0.25
	vmul.xy		VUR(vf23), VUR(vf9), VUR(vf23)
	#vmul.p		VUR(vf23), VUR(vf9), VUR(vf23)			// X * X * X * 0.25, Y * Y * Y * 0.25
	vmul.xy		VUR(vf23), VUR(vf9), VUR(vf23)
	#vsub.p		VUR(vf10), VUR(vf10), VUR(vf23)			// result -= X * X * X * 0.25
	vsub.xy		VUR(vf10), VUR(vf10), VUR(vf23)
	qmfc2		$v1, VUR(vf10)
	sw			$v1, 0x30($a3)				// Store Texture.x
	dsrl32		$v1, $v1, 0
	b			vtx_done_CBFD
	sw			$v1, 0x34($a3)				// Store Texture.y
		
do_texgen_CBFD:
# EnvMapped G_TEXTURE_GEN  t.x = 0.5 * (1.0 + n.x) t.y = 0.5 * (1.0 + n.y)
	#vadd.p		VUR(vf9), VUR(vf9)[1,1], VUR(vf9)		// 1+x, 1+y
	vaddw.xy	VUR(vf9), VUR(vf9), VUR(vf0w)
	#vmul.p		VUR(vf9), VUR(vf9)[1/2,1/2], VUR(vf9)	// X * 0.5, Y * 0.5
	lui			$v1, 0x3f00				// 0.5
	pextlw		$v1, $v1, $v1
	qmtc2		$v1, VUR(vf22)
	vmul.xy		VUR(vf9), VUR(vf9), VUR(vf22)
	qmfc2		$v1, VUR(vf9)
	sw			$v1, 0x30($a3)				// Store Texture.x
	dsrl32		$v1, $v1, 0
	b			vtx_done_CBFD
	sw			$v1, 0x34($a3)				// Store Texture.y
		
do_texture_CBFD:
# Textured t.x = (float)v.tu * mTextureScale.x 	t.y = (float)v.tv * mTextureScale.y
	#lv.s		VUR(vf11x), 8($a2)				// load texture word [tv,tu] (N.B. due to swizzling these are 'backwards' from what you might expect)
	lw			$v1, 8($a2)
	#vs2i.s		VUR(vf11), VUR(vf11x)
	pextlh		$v1, $v1, $zero
	qmtc2		$v1, VUR(vf11)
	#vi2f.p		VUR(vf11), VUR(vf11), 16				// int -> float
	vitof15.xy	VUR(vf11), VUR(vf11)
	lui			$v1, 0x3f00				// 0.5
	qmtc2		$v1, VUR(vf22)
	vmulx.xy	VUR(vf11), VUR(vf11), VUR(vf22x)
	#vmul.p		VUR(vf11), VUR(vf11), VUR(vf19zw)			// multiply by mTextureScale
	vmulz.y		VUR(vf11), VUR(vf11), VUR(vf19z)
	vmulw.x		VUR(vf11), VUR(vf11), VUR(vf19w)
	#sv.s		VUR(vf11y), 0x30($a3)				// Store Texture.x
	#sv.s		VUR(vf11x), 0x34($a3)				// Store Texture.y
	qmfc2		$v1, VUR(vf11)
	sw			$v1, 0x34($a3)
	dsrl32		$v1, $v1, 0
	sw			$v1, 0x30($a3)

vtx_done_CBFD:
	sqc2		VUR(vf24), 0x20($a3)				// Store colour

# Continue with the next vertex
	addiu		$t3, $t3, 2					// inc v0 counter
	addiu		$a2, $a2, 16				// Next input vertex
	bne			$a2, $t0, next_vertex_CBFD
	addiu		$a3, $a3, 64				// Next output vertex

finished_CBFD:	
	jr			$ra
	nop
	
############################
.global _TnLVU0PD
############################
#	a0 - world matrix				- must be aligned to 16 bytes
#	a1 - world*projection matrix	- must be aligned to 16 bytes
#	a2 - Fiddled vertices			- stride 16
#	a3 - Output vertices			- must be aligned to 16 bytes, stride 64
#	t0 - num vertices
#	t1 - params
#	t2 - CI pointer

# Lighting calculation
# M000: World Matrix
# M100: Projection Matrix
# VUR(vf9): Material normal 
# VUR(vf10): Accumulated colour
# VUR(vf11): ?
# VUR(vf12): ?
# VUR(vf13): ?
# VUR(vf14): Light normal
# VUR(vf15): Light colour
# VUR(vf16): Scratch
# VUR(vf17): current vertex Alpha value
# VUR(vf18): Ambient
# VUR(vf19zw): Texture X & Y scale
# t4 = cur_light
# t6 = first_light
# t7 = last_light
# v0 = TnLFlags
# v1 = color index pointer

_TnLVU0PD:
	lqc2		VUR(vf1), 0($a0)				// Load mat world
	lqc2		VUR(vf2), 16($a0)
	lqc2		VUR(vf3), 32($a0)
	lqc2		VUR(vf4), 48($a0)

	lqc2		VUR(vf5), 0($a1)				// Load mat project
	lqc2		VUR(vf6), 16($a1)
	lqc2		VUR(vf7), 32($a1)
	lqc2		VUR(vf8), 48($a1)
	
	lqc2		VUR(vf19), PARAMS_FLAGS_NLIGHT_TXSCAL($t1)	// Load params [Flags, Num_lights, tscale_x, tscale_y]
	#vmov.p		VUR(vf19zw), VUR(vf19zw)[y,x]				// Swizzle texture X&Y scale 
	vmr32.y		VUR(vf22), VUR(vf19)						// [?, tscale_x, ?, ?]
	vmr32.x		VUR(vf22), VUR(vf22)						// [tscale_x, ?, ?, ?]
	vmr32.z		VUR(vf19), VUR(vf19)						// [?, ?, tscale_y, ?]
	vmr32.w		VUR(vf19), VUR(vf22)						// [?, ?, tscale_y, tscale_x]
	#mfv		$t7, VUR(vf19y)					// Num_lights
	qmfc2		$t7, VUR(vf19)
	dsrl32 		$t7, $t7, 0
	
# Calculate the last light index
	addiu		$t6, $t1, PARAMS_LIGHTS		// pointer to first_light = p_lights
	sll			$t7, $t7, LIGHTSZ			// num_lights*64
	addu		$t7, $t6, $t7				// last_light = p_lights + num_lights*64
	lqc2		VUR(vf18), LIGHTCOL($t7)			// Load ambient color
	
	sll			$v1, $t0, 2					// count * 4
	sll			$t0, $t0, 3					// count * 8
	addu		$t0, $v1, $t0				// count = count * 12
	addu		$t0, $a2, $t0				// end_ptr = start_ptr + count * 12
	beq			$a2, $t0, finished_PD
	#mfv		$v0, VUR(vf19x)					// TnL flags
	qmfc2		$v0, VUR(vf19)

next_vertex_PD:
# Load and transform this vertex position
 	#lv.s		VUR(vf12x), 0($a2)				// load word [y,x,?,z]
 	#lv.s		VUR(vf12y), 4($a2)				// ulqc2 is buggy on PHAT
	ld			$v1, 0($a2)					// [y,x,?,z]
	#vs2i.p		VUR(vf9), VUR(vf12)					// VUR(vf9) = [?,z,y,x]
	pextlh		$v1, $v1, $zero
	qmtc2		$v1, VUR(vf9)
	#vi2f.q		VUR(vf9), VUR(vf9), 16				// int -> float
	vitof15.xyzw	VUR(vf9), VUR(vf9)
	lui			$t3, 0x3f00				// 0.5
	qmtc2		$t3, VUR(vf22)
	vmulx.xyzw	VUR(vf9), VUR(vf9), VUR(vf22x)
	#vmov.q		VUR(vf9), VUR(vf9)[y,x,w,1]
	vmr32.xz	VUR(vf22), VUR(vf9)
	vaddx.y		VUR(vf9), VUR(vf0), VUR(vf9x)
	vmove.xz	VUR(vf9), VUR(vf22)
	vmove.w		VUR(vf9), VUR(vf0)
	#vtfm4.q	VUR(vf10), M000, VUR(vf9)			// World transform
	vmulax.xyzw     VUR(ACC), VUR(vf1), VUR(vf9)
    vmadday.xyzw    VUR(ACC), VUR(vf2), VUR(vf9)
    vmaddaz.xyzw    VUR(ACC), VUR(vf3), VUR(vf9)
    vmaddw.xyzw     VUR(vf10), VUR(vf4), VUR(vf9)
 	#mfv			$v1, VUR(vf12y)					// Get Cindx
	pcpyud		$v1, $v1, $zero
	srl			$v1, $v1, 16
 	andi		$v1, 0xFF					// use only low Byte
	addu		$v1, $v1, $t2				// pointer = base vector + Cindx
	#vtfm4.q		VUR(vf11), M100, VUR(vf10)			// Projection transform
	vmulax.xyzw     VUR(ACC), VUR(vf5), VUR(vf10)
    vmadday.xyzw    VUR(ACC), VUR(vf6), VUR(vf10)
    vmaddaz.xyzw    VUR(ACC), VUR(vf7), VUR(vf10)
    vmaddw.xyzw     VUR(vf11), VUR(vf8), VUR(vf10)
	sqc2		VUR(vf10), 0x00($a3)				// Store world transform
	sqc2		VUR(vf11), 0x10($a3)				// Store projection transform
	
# Compute the clip flags
	#vcmp.q		LT, VUR(vf11), VUR(vf11)[-w,-w,-w,0]	// x < -w, y < -w, z < -w
	#vnop
	#mfvc		$t4, $131					// VU0_CC. Corresponds to X_NEG/Y_NEG/Z_NEG (will become X_POS/Y_POS/Z_POS later)
	#vcmp.q		GT, VUR(vf11), VUR(vf11)[w,w,w,0]		// x > w, y > w, z > w
	#andi		$t4, $t4, 0x7				// Mask out the condition codes we dont care about
	#sll			$t4, $t4, 3					// Shift up to create X_POS/Y_POS/Z_POS	
	#mfvc		$t5, $131					// VU0_CC. Corresponds to X_NEG/Y_NEG/Z_NEG
	#andi		$t5, $t5, 0x7				// Mask out the condition codes we dont care about
	#or			$t5, $t4, $t5
	vclipw.xyz	VUR(vf11), VUR(vf11w)
	vnop
	vnop
	vnop
	vnop
	vnop
	cfc2		$t5, $vi18
	andi		$t5, 0x3F

#Load vertex Normal or Color
	#lv.s		VUR(vf9x), 0($v1)				// load normal word [w,z,y,x]
	andi		$t4, $v0, TNL_LIGHT			// if( TNL_LIGHT )
	beqz		$t4, do_color_PD
	sw			$t5, 0x38($a3)				// Store ClipFlags
	
#Do lighting Convert the alpha in VUR(vf9) to float and pass it along to light color
	#.word		0xd0380000 | (8<<8) | (43)	// vuc2i.s	VUR(vf12), VUR(vf9x)					// VUR(vf9) = [?,z,y,x]
	#vi2f.s		VUR(vf17w), VUR(vf12x), 31				// int -> float, VUR(vf17) = [a * 1/256]
	lw			$t3, 0($v1)
	pextlb		$t3, $t3, $t3
	pextlh		$t3, $t3, $t3			// [a,z,y,x]
	psrlw		$t3, $t3, 1
	qmtc2		$t3, VUR(vf17)
	vitof0.x	VUR(vf22), VUR(vf17)
	vmr32.w		VUR(vf17), VUR(vf22)
	lui			$t3, 0x3000
	qmtc2		$t3, VUR(vf22)
	vmulx.w		VUR(vf17), VUR(vf17), VUR(vf22x)
	
# Convert the normal in VUR(vf9) to float and transform
	#.word		0xd0398080 | (8<<8) | (40)	// vc2i.s		VUR(vf9), VUR(vf9x)					// VUR(vf9) = [?,z,y,x]
	#vi2f.q		VUR(vf10), VUR(vf9)[w,z,y,x], 0		// int -> float, Unfiddle (obliterates world transform)
	lw			$t3, 0($v1)
	pextlb		$t3, $t3, $zero
	pextlh		$t3, $t3, $zero			// [a,z,y,x]
	qmtc2		$t3, VUR(vf9)
	vitof0.xyzw	VUR(vf10), VUR(vf9)
	vmr32.xyzw	VUR(vf10), VUR(vf10)				// [z,y,x,a]
	vmr32.xyzw	VUR(vf22), VUR(vf10)				// [y,x,a,z]
	vmr32.xz	VUR(vf10), VUR(vf22)				// [x,y,z,a]
	#vtfm3.t	VUR(vf9), M000, VUR(vf10)			// Transform with world matrix (only need 3x3)//Corn
	vmulax.xyz  VUR(ACC), VUR(vf1), VUR(vf10)
    vmadday.xyz VUR(ACC), VUR(vf2), VUR(vf10)
    vmaddz.xyz  VUR(vf9), VUR(vf3), VUR(vf10)
	#vdot.t		VUR(vf10x), VUR(vf9), VUR(vf9)			// VUR(vf10x) = x*x + y*y + z*z
	vmul.xyz	VUR(vf10), VUR(vf9), VUR(vf9)
	vaddy.x		VUR(vf10), VUR(vf10), VUR(vf10y)
	vaddz.x		VUR(vf10), VUR(vf10), VUR(vf10z)
	#vrsq.s		VUR(vf10x), VUR(vf10x)					// VUR(vf10x) = 1/sqrt(x*x + y*y + z*z)
	vrsqrt		VUR(Q), VUR(vf0w), VUR(vf10x)
	vwaitq
	#vscl.t		VUR(vf9), VUR(vf9), VUR(vf10x)			// VUR(vf9x) = v.normalise().
	vmulq.xyz   VUR(vf9), VUR(vf9), VUR(Q)

	#vmov.q		VUR(vf10), VUR(vf18)					// Colour = ambient
	vmove.xyzw	VUR(vf10), VUR(vf18)
	beq			$t6, $t7, done_lighting_PD	// cur_light == last_light?
	or			$t4, $t6, $0				// cur_light = p_lights

next_light_PD:
	lqc2		VUR(vf14), LIGHTDIR($t4)			// Load Light normal
	#vdot.t		VUR(vf16x)[0:1], VUR(vf9), VUR(vf14)		// x = clamp(dot(normal,(x,y,z)),0,1)
	vmul.xyz	VUR(vf16), VUR(vf9), VUR(vf14)
	vaddy.x		VUR(vf16), VUR(vf16), VUR(vf16y)
	vaddz.x		VUR(vf16), VUR(vf16), VUR(vf16z)
	vminiw.x	VUR(vf16), VUR(vf16), VUR(vf0w)
	vmaxx.x		VUR(vf16), VUR(vf16), VUR(vf0x)
	lqc2		VUR(vf15), LIGHTCOL($t4)			// Load Light colour
	addiu		$t4, $t4, (1<<LIGHTSZ)		// Skip to the next light
	#vscl.t		VUR(vf16), VUR(vf15), VUR(vf16x)			// r,g,b = r*x, g*x, b*x
	vmulx.xyz	VUR(vf16), VUR(vf15), VUR(vf16x)
	bne			$t4, $t7, next_light_PD
	#vadd.t		VUR(vf10), VUR(vf10), VUR(vf16)			// col += r,g,b,a
	vadd.xyz	VUR(vf10), VUR(vf10), VUR(vf16)

done_lighting_PD:
	#vmov.t		VUR(vf17)[0:1,0:1,0:1], VUR(vf10)		// Clamp 0..1 and merge with vertex alpha in VUR(vf17w)
	vmove.xyz	VUR(vf17), VUR(vf10)
	vminiw.xyz	VUR(vf17), VUR(vf17), VUR(vf0w)
	vmaxx.xyz	VUR(vf17), VUR(vf17), VUR(vf0x)

	andi		$t4, $v0, TNL_TEXGEN		// if( TNL_TEXGEN )
	beqz		$t4, do_texture_PD
	sqc2		VUR(vf17), 0x20($a3)				// Store colour

	andi		$t4, $v0, TNL_TEXGENLIN		// if( TNL_TEXGENLIN )
	beqz		$t4, do_texgen_PD
	nop
	
# EnvMapped G_TEXTURE_GEN_LINEAR  Cheap way to do acos(x)/PI -> 0.5f - 0.25f * x - 0.25f * x * x * x //Corn
	#vmul.p		VUR(vf11z), VUR(vf11)[1/4,1/4], VUR(vf9)	// X * 0.25, Y * 0.25
	lui			$t3, 0x3e80				// 0.25
	qmtc2		$t3, VUR(vf22)
	vmulx.xy	VUR(vf11), VUR(vf9), VUR(vf22x)
	lui			$t3, 0x3f00				// 0.5
	pextlw		$t3, $t3, $t3
	qmtc2		$t3, VUR(vf22)
	#vsub.p		VUR(vf12), VUR(vf11)[1/2,1/2], VUR(vf11z)	// result = 0.5 - X * 0.25
	vsub.xy		VUR(vf12), VUR(vf22), VUR(vf11)
	#vmul.p		VUR(vf11z), VUR(vf9), VUR(vf11z)			// X * X * 0.25, Y * Y * 0.25
	vmul.xy		VUR(vf11), VUR(vf9), VUR(vf11)
	#vmul.p		VUR(vf11z), VUR(vf9), VUR(vf11z)			// X * X * X * 0.25, Y * Y * Y * 0.25
	vmul.xy		VUR(vf11), VUR(vf9), VUR(vf11)
	#vsub.p		VUR(vf12), VUR(vf12), VUR(vf11z)			// result -= X * X * X * 0.25
	vsub.xy		VUR(vf12), VUR(vf12), VUR(vf11)
	qmfc2		$t3, VUR(vf12)
	#sv.s		VUR(vf12x), 0x30($a3)				// Store Texture.x
	sw			$t3, 0x30($a3)
	dsrl32		$t3, $t3, 0
	b			vtx_done_PD
	#sv.s		VUR(vf12y), 0x34($a3)				// Store Texture.y
	sw			$t3, 0x34($a3)
		
do_texgen_PD:
# EnvMapped G_TEXTURE_GEN  t.x = 0.5 * (1.0 + n.x) t.y = 0.5 * (1.0 + n.y)
	#vadd.p		VUR(vf11), VUR(vf11)[1,1], VUR(vf9)		// 1+x, 1+y
	vaddw.xy	VUR(vf11), VUR(vf9), VUR(vf0w)
	#vmul.p		VUR(vf11), VUR(vf11)[1/2,1/2], VUR(vf11)	// X * 0.5, Y * 0.25
	lui			$t3, 0x3f00				// 0.5
	qmtc2		$t3, VUR(vf22)
	vmulx.xy	VUR(vf11), VUR(vf11), VUR(vf22x)
	qmfc2		$t3, VUR(vf11)
	#sv.s		VUR(vf11x), 0x30($a3)				// Store Texture.x
	sw			$t3, 0x30($a3)
	b			vtx_done_PD
	#sv.s		VUR(vf11y), 0x34($a3)				// Store Texture.y
	sw			$t3, 0x34($a3)
		
do_color_PD:
# Normalise the RGBA colour
	#.word		0xd0380000 | (8<<8) | (40)	// vuc2i.s	VUR(vf9), VUR(vf9x)					// VUR(vf9) = [a,b,g,r]
	lw			$t3, 0($v1)
	pextlb		$t3, $t3, $t3
	pextlh		$t3, $t3, $t3			// [a,b,g,r]
	psrlw		$t3, $t3, 1
	qmtc2		$t3, VUR(vf9)
	vmr32.xyzw	VUR(vf22), VUR(vf9)				// [b,g,r,a]
	vaddz.x		VUR(vf22), VUR(vf0), VUR(vf22z)		// [r,g,r,a]
	vaddy.z		VUR(vf22), VUR(vf0), VUR(vf9y)			// [r,g,b,a]
	#vi2f.q		VUR(vf9), VUR(vf9)[w,z,y,x], 31		// int -> float, VUR(vf9) = [r * 1/256, g * 1/256, b * 1/256, a * 1/256]
	vitof0.xyzw	VUR(vf9), VUR(vf22)
	lui			$t3, 0x3000
	qmtc2		$t3, VUR(vf22)
	vmulx.xyzw	VUR(vf9), VUR(vf9), VUR(vf22x)
	sqc2		VUR(vf9), 0x20($a3)				// Store colour

do_texture_PD:
# Textured t.x = (float)v.tu * mTextureScale.x t.y = (float)v.tv * mTextureScale.y
	#lv.s		VUR(vf11x), 8($a2)				// load texture word [tv,tu] (N.B. due to swizzling these are 'backwards' from what you might expect)
	#vs2i.s		VUR(vf11), VUR(vf11x)
	lw			$t3, 8($a2)
	pextlh		$t3, $t3, $zero
	qmtc2		$t3, VUR(vf11)
	#vi2f.p		VUR(vf11), VUR(vf11), 16				// int -> float
	vitof15.xy	VUR(vf11), VUR(vf11)
	lui			$t3, 0x3f00				// 0.5
	qmtc2		$t3, VUR(vf22)
	vmulx.xy	VUR(vf11), VUR(vf11), VUR(vf22x)
	#vmul.p		VUR(vf11), VUR(vf11), VUR(vf19zw)			// multiply by mTextureScale
	vmulz.y		VUR(vf11), VUR(vf11), VUR(vf19z)
	vmulw.x		VUR(vf11), VUR(vf11), VUR(vf19w)
	#sv.s		VUR(vf11y), 0x30($a3)				// Store Texture.x
	#sv.s		VUR(vf11x), 0x34($a3)				// Store Texture.y
	qmfc2		$t3, VUR(vf11)
	sw			$t3, 0x34($a3)
	dsrl32		$t3, $t3, 0
	sw			$t3, 0x30($a3)

vtx_done_PD:
# Continue with the next vertex
	addiu		$a2, $a2, 12				// Next input vertex
	bne			$a2, $t0, next_vertex_PD
	addiu		$a3, $a3, 64				// Next output vertex

finished_PD:	
	jr			$ra
	nop
	

############################
.global _TnLVU0DKR
############################
#	a0 - num vertices
#	a1 - world*projection matrix	- must be aligned to 16 bytes
#	a2 - Fiddled vertices			- stride 16
#	a3 - Output vertices			- must be aligned to 16 bytes, stride 64

_TnLVU0DKR:
	lqc2		VUR(vf5), 0($a1)				// Load mat worldproject
	lqc2		VUR(vf6), 16($a1)
	lqc2		VUR(vf7), 32($a1)
	lqc2		VUR(vf8), 48($a1)
	
	sll			$v0, $a0, 1					// count * 2
	sll			$a0, $a0, 3					// count * 8
	addu		$a0, $v0, $a0				// count = count * 10
	addu		$a0, $a2, $a0				// end_ptr = start_ptr + count * 10
	beq			$a2, $a0, finished_DKR
	#vone.s		VUR(vf12w)						// w = 1.0f
	vmove.w		VUR(vf12), VUR(vf0)
	
next_vertex_DKR:
# Load and transform this vertex position
 	xori		$v0, $a2, 0x2				// = vtx_ptr ^ 2
	lh			$t4, 0($v0)					// get vertex x coord	
	#mtv		$t4, VUR(vf12x)					// store on VU0
	addiu		$a2, $a2, 0x2				// = vtx_ptr + 2
 	xori		$v0, $a2, 0x2				// = vtx_ptr ^ 2
	lh			$t5, 0($v0)					// get vertex y coord
	#mtv		$t4, VUR(vf12y)					// store on VU0
	addiu		$a2, $a2, 0x2				// = vtx_ptr + 2
 	xori		$v0, $a2, 0x2				// = vtx_ptr ^ 2
	lh			$t6, 0($v0)					// get vertex z coord
	pextlw		$t4, $t6, $t4
	#mtv		$t4, VUR(vf12z)					// store on VU0
	addiu		$a2, $a2, 0x2				// = vtx_ptr + 2
	pextlw		$t4, $t5, $t4
	qmtc2		$t4, VUR(vf12)
	vmove.w		VUR(vf12), VUR(vf0)

	#vi2f.t		VUR(vf12), VUR(vf12), 0				// int -> float (x,y,z,1)
	vitof0.xyz	VUR(vf12), VUR(vf12)
	#vtfm4.q	VUR(vf11), M100, VUR(vf12)			// Projection transform
	vmulax.xyzw     VUR(ACC), VUR(vf5), VUR(vf12)
    vmadday.xyzw    VUR(ACC), VUR(vf6), VUR(vf12)
    vmaddaz.xyzw    VUR(ACC), VUR(vf7), VUR(vf12)
    vmaddw.xyzw     VUR(vf11), VUR(vf8), VUR(vf12)

	sqc2		VUR(vf12), 0x00($a3)				// Store world transform
	sqc2		VUR(vf11), 0x10($a3)				// Store world+projection transform
	
# Compute the clip flags
	#vcmp.q		LT, VUR(vf11), VUR(vf11)[-w,-w,-w,0]	// x < -w, y < -w, z < -w
	#vnop
	#mfvc		$t4, $131					// VU0_CC. Corresponds to X_NEG/Y_NEG/Z_NEG (will become X_POS/Y_POS/Z_POS later)
	#vcmp.q		GT, VUR(vf11), VUR(vf11)[w,w,w,0]		// x > w, y > w, z > w
	#andi		$t4, $t4, 0x7				// Mask out the condition codes we dont care about
	#sll			$t4, $t4, 3					// Shift up to create X_POS/Y_POS/Z_POS	
	#mfvc		$t5, $131					// VU0_CC. Corresponds to X_NEG/Y_NEG/Z_NEG
	#andi		$t5, $t5, 0x7				// Mask out the condition codes we dont care about
	#or			$t4, $t4, $t5
	vclipw.xyz	VUR(vf11), VUR(vf11w)
	vnop
	vnop
	vnop
	vnop
	vnop
	cfc2		$t4, $vi18
	andi		$t4, 0x3F
	sw			$t4, 0x38($a3)				// Store ClipFlags

# Normalise the RGBA colour
 	xori		$v0, $a2, 0x2				// = vtx_ptr ^ 2
	lhu			$t4, 0($v0)					// get vertex color	(hi)
	addiu		$a2, $a2, 0x2				// = vtx_ptr + 2
 	xori		$v0, $a2, 0x2				// = vtx_ptr ^ 2
	lhu			$t5, 0($v0)					// get vertex color (lo)
	sll			$t4, $t4, 16				// pack
 	or		    $t5, $t5, $t4				// to 32bit
	addiu		$a2, $a2, 0x2				// = vtx_ptr + 2
	#mtv		$t5, VUR(vf9x)					// store on VU0

	#.word		0xd0380000 | (8<<8) | (40)	// vuc2i.s	VUR(vf9), VUR(vf9x)					// VUR(vf9) = [a,b,g,r]
	pextlb		$t5, $t5, $t5
	pextlh		$t5, $t5, $t5			// [a,b,g,r]
	psrlw		$t5, $t5, 1
	qmtc2		$t5, VUR(vf9)
	vmr32.xyzw	VUR(vf22), VUR(vf9)				// [b,g,r,a]
	vaddz.x		VUR(vf22), VUR(vf0), VUR(vf22z)		// [r,g,r,a]
	vaddy.z		VUR(vf22), VUR(vf0), VUR(vf9y)			// [r,g,b,a]
	#vi2f.q		VUR(vf9), VUR(vf9)[w,z,y,x], 31		// int -> float, VUR(vf9) = [r * 1/256, g * 1/256, b * 1/256, a * 1/256]
	vitof0.xyzw	VUR(vf9), VUR(vf22)
	lui			$t5, 0x3000
	qmtc2		$t5, VUR(vf22)
	vmulx.xyzw	VUR(vf9), VUR(vf9), VUR(vf22x)
	sqc2		VUR(vf9), 0x20($a3)				// Store colour

# Continue with the next vertex
	bne			$a2, $a0, next_vertex_DKR
	addiu		$a3, $a3, 64				// Next output vertex

finished_DKR:	
	jr			$ra
	nop

############################
.global _TnLVU0DKRB
############################
#	a0 - num vertices
#	a1 - world*projection matrix	- must be aligned to 16 bytes
#	a2 - Fiddled vertices			- stride 16
#	a3 - Output vertices			- must be aligned to 16 bytes, stride 64

_TnLVU0DKRB:
	lqc2		VUR(vf5), 0($a1)				// Load mat worldproject (matrix[0] and only 3x3 is needed)
	lqc2		VUR(vf6), 16($a1)
	lqc2		VUR(vf7), 32($a1)

	#lv.s		VUR(vf1x), 128($a1)				// Load element 0 in matrix[2]
	lw			$t2, 128($a1)
	#lv.s		VUR(vf1z), 168($a1)				// Load element 10 in matrix[2]
	lw			$t3, 168($a1)
	qmtc2		$t2, VUR(vf22)
	vmove.x		VUR(vf1), VUR(vf22)
	qmtc2		$t3, VUR(vf22)
	vaddx.z		VUR(vf1), VUR(vf0), VUR(vf22x)

	#vmov.s		VUR(vf1y), VUR(vf1x)					// Copy element 0 (instead of 5)
	vaddx.y		VUR(vf1), VUR(vf0), VUR(vf1x)
	#VUR(vf)im.s		VUR(vf2y), 0.375					// Y scale factor
	lui			$t3, 0x3ec0				// 0.375
	qmtc2		$t3, VUR(vf22)
	vaddx.y		VUR(vf2), VUR(vf0), VUR(vf22x)
	#vmul.t		VUR(vf1), VUR(vf1), VUR(vf2)[1/2,y,1/2]	// Prepare X and Z scaling values  
	lui			$t3, 0x3f00				// 0.5
	qmtc2		$t3, VUR(vf22)
	vmul.y		VUR(vf1), VUR(vf1), VUR(vf2)
	vmulx.xz	VUR(vf1), VUR(vf1), VUR(vf22x)
	#vscl.t		C100, C100, VUR(vf1x)			// Scale X matrix colum 
	vmul.x		VUR(vf5), VUR(vf5), VUR(vf1)
	vmul.x		VUR(vf6), VUR(vf6), VUR(vf1)
	vmul.x		VUR(vf7), VUR(vf7), VUR(vf1)
	#vscl.t		C110, C110, VUR(vf1y)			// Scale Y matrix colum 
	vmul.y		VUR(vf5), VUR(vf5), VUR(vf1)
	vmul.y		VUR(vf6), VUR(vf6), VUR(vf1)
	vmul.y		VUR(vf7), VUR(vf7), VUR(vf1)
	#vscl.t		C120, C120, VUR(vf1z)			// Scale Z matrix colum 
	vmul.z		VUR(vf5), VUR(vf5), VUR(vf1)
	vmul.z		VUR(vf6), VUR(vf6), VUR(vf1)
	vmul.z		VUR(vf7), VUR(vf7), VUR(vf1)
	lqc2		VUR(vf4), -64($a3)				// Get base vector to add to the billbord geometry (in position 0)

	sll			$v0, $a0, 1					// count * 2
	sll			$a0, $a0, 3					// count * 8
	addu		$a0, $v0, $a0				// count = count * 10
	addu		$a0, $a2, $a0				// end_ptr = start_ptr + count * 10
	beq			$a2, $a0, finished_DKRB
	#vone.s		VUR(vf12w)						// w = 1.0f
	vmove.w		VUR(vf12), VUR(vf0)
	
next_vertex_DKRB:
# Load and transform this vertex position
 	xori		$v0, $a2, 0x2				// = vtx_ptr ^ 2
	lh			$t4, 0($v0)					// get vertex x coord	
	#mtv		$t4, VUR(vf12x)					// store on VU0
	addiu		$a2, $a2, 0x2				// = vtx_ptr + 2
 	xori		$v0, $a2, 0x2				// = vtx_ptr ^ 2
	lh			$t5, 0($v0)					// get vertex y coord
	#mtv		$t4, VUR(vf12y)					// store on VU0
	addiu		$a2, $a2, 0x2				// = vtx_ptr + 2
 	xori		$v0, $a2, 0x2				// = vtx_ptr ^ 2
	lh			$t6, 0($v0)					// get vertex z coord
	#mtv		$t4, VUR(vf12z)					// store on VU0
	addiu		$a2, $a2, 0x2				// = vtx_ptr + 2
	pextlw		$t4, $t6, $t4
	pextlw		$t4, $t5, $t4
	qmtc2		$t4, VUR(vf12)
	vmove.w		VUR(vf12), VUR(vf0)
	#vi2f.t		VUR(vf12), VUR(vf12), 0				// int -> float (x,y,z,1)
	vitof0.xyz	VUR(vf12), VUR(vf12)
	#vtfm3.t	VUR(vf11), M100, VUR(vf12)			// 3x3 transform
	vmulax.xyz    VUR(ACC), VUR(vf5), VUR(vf12)
    vmadday.xyz   VUR(ACC), VUR(vf6), VUR(vf12)
    vmaddz.xyz    VUR(vf11), VUR(vf7), VUR(vf12)

# Clip flags
	sw			$zero, 0x38($a3)			// Clear ClipFlags

	#vadd.t		VUR(vf12), VUR(vf11), VUR(vf4)			// Add basevector
	vadd.xyz	VUR(vf12), VUR(vf11), VUR(vf4)
	sqc2		VUR(vf12), 0x00($a3)				// Store world transform (x,y,z,1)
	

# Normalise the RGBA colour
 	xori		$v0, $a2, 0x2				// = vtx_ptr ^ 2
	lhu			$t4, 0($v0)					// get vertex color	(hi)
	addiu		$a2, $a2, 0x2				// = vtx_ptr + 2
 	xori		$v0, $a2, 0x2				// = vtx_ptr ^ 2
	lhu			$t5, 0($v0)					// get vertex color (lo)
	sll			$t4, $t4, 16				// pack
 	or		    $t5, $t5, $t4				// to 32bit
	addiu		$a2, $a2, 0x2				// = vtx_ptr + 2
	#mtv		$t5, VUR(vf9x)					// store on VU0

	#.word		0xd0380000 | (8<<8) | (40)	// vuc2i.s	VUR(vf9), VUR(vf9x)					// VUR(vf9) = [a,b,g,r]
	pextlb		$t5, $t5, $t5
	pextlh		$t5, $t5, $t5			// [a,b,g,r]
	psrlw		$t5, $t5, 1
	qmtc2		$t5, VUR(vf9)
	vmr32.xyzw	VUR(vf22), VUR(vf9)				// [b,g,r,a]
	vaddz.x		VUR(vf22), VUR(vf0), VUR(vf22z)		// [r,g,r,a]
	vaddy.z		VUR(vf22), VUR(vf0), VUR(vf9y)			// [r,g,b,a]
	#vi2f.q		VUR(vf9), VUR(vf9)[w,z,y,x], 31		// int -> float, VUR(vf9) = [r * 1/256, g * 1/256, b * 1/256, a * 1/256]
	vitof0.xyzw	VUR(vf9), VUR(vf22)
	lui			$t5, 0x3000
	qmtc2		$t5, VUR(vf22)
	vmulx.xyzw	VUR(vf9), VUR(vf9), VUR(vf22x)
	sqc2		VUR(vf9), 0x20($a3)				// Store colour

# Continue with the next vertex
	bne			$a2, $a0, next_vertex_DKRB
	addiu		$a3, $a3, 64				// Next output vertex

finished_DKRB:	
	jr			$ra
	nop
	
.set pop

#define ABI_EABI64
#include "as_reg_compat.h"

#if __GNUC__ > 3
#define VUR(x) $x
#else
#define VUR(x) x
#endif

	.set noat

	
	.global		_ClipToHyperPlane

.text
	.set		push
	.set		noreorder
	
###############################################################################
#
#	a0		dest vertices			- must be aligned to 16 bytes
#	a1		source vertices			- must be aligned to 16 bytes
#	a2		plane					- must be aligned to 16 bytes
#	a3		in_vertex_count			- must be > 0 or we need to re apply check
#
#	v0		out_vertex_count
#
#	Trashes M000, M100, M200, M300
#
_ClipToHyperPlane:

	#
	#	a0			- current_dest
	#	a1			- current_source
	#	a2			- source (copy of original)
	#	a3			- verts_remaining
	#	t0			- temp
	#	t1			- source_end
	#	VUR(vf1)		- plane
	#	VUR(vf3x),013	- aDotPlane, bDotPlane, ...
	#	M100		- clipped_out
	#	M200		- a
	#	M300		- b
	#
	
	//beq			$a3, $0, finished_all_vertices	// verts_remaining == 0 --> finished_all_vertices
	//nop

	lqc2		VUR(vf1), 0($a2)				// load plane equation (we reuse a2 for another purpose)
	
	or			$a2, $a1, $0				// take a copy of the original source pointer
	sll			$t1, $a3, 6					// t1 = num_verts*64
	addu		$t1, $a1, $t1				// source_end = source + num_verts*64
	
	// load initial values for b
	lqc2		VUR(vf10), 0($a1)				// TransformedPos(V4)
	lqc2		VUR(vf11), 16($a1)				// ProjectedPos(V4)
	lqc2		VUR(vf12), 32($a1)				// Color(V4)
	lqc2		VUR(vf13), 48($a1)				// Texture(V2) + Clipflags + 1/w
	addiu		$a1, $a1, 64				// skip the first vertex

	#vdot.q		VUR(vf2x), VUR(vf11), VUR(vf1)			// bDotPlane = dot( b.ProjectedPos, plane )
	vmul.xyzw	VUR(vf2), VUR(vf11), VUR(vf1)
	vaddy.x		VUR(vf2), VUR(vf2), VUR(vf2y)
	vaddz.x		VUR(vf2), VUR(vf2), VUR(vf2z)
	vaddw.x		VUR(vf2), VUR(vf2), VUR(vf2w)

	or			$v0, $0, $0					// out_count = 0
	
get_next_vertex:
	// Wrap around the source pointer if necessary
	bne			$a1, $t1, load_a
	nop
	or			$a1, $a2, $0				// current_source = source

load_a:
	lqc2		VUR(vf5), 16($a1)
	lqc2		VUR(vf4), 0($a1)				// load a
	#vdot.q		VUR(vf3x), VUR(vf5), VUR(vf1)			// aDotPlane = dot( a.ProjectedPos, plane )
	vmul.xyzw	VUR(vf3), VUR(vf5), VUR(vf1)
	vaddy.x		VUR(vf3), VUR(vf3), VUR(vf3y)
	vaddz.x		VUR(vf3), VUR(vf3), VUR(vf3z)
	vaddw.x		VUR(vf3), VUR(vf3), VUR(vf3w)
	lqc2		VUR(vf6), 32($a1)
	#vcmp.s		GT, VUR(vf3x), VUR(vf3x)[0]
	qmfc2		$t0, VUR(vf3)
	pextlw		$t0, $t0, $t0		//extend sign bit
	lqc2		VUR(vf7), 48($a1)

	bgtz		$t0, a_is_outside				// aDotPlane > 0 --> a_is_outside
	nop
	
a_is_inside:
	#vcmp.s		LE, VUR(vf2x), VUR(vf2x)[0]
	qmfc2		$t0, VUR(vf2)
	pextlw		$t0, $t0, $t0		//extend sign bit
	blez		$t0, a_is_inside_copy			// bDotPlane <= 0 --> a_is_inside_copy
	nop

	
	// Calculate the parametric intersection point
	vsub.xyzw	VUR(vf8), VUR(vf11), VUR(vf5)			// VUR(vf8) = b.ProjectedPos - a.ProjectedPos
	#vdot.q		VUR(vf9x), VUR(vf8), VUR(vf1)			// VUR(vf9x) = dot( (b.ProjectedPos - a.ProjectedPos), plane )
	vmul.xyzw	VUR(vf9), VUR(vf8), VUR(vf1)
	vaddy.x		VUR(vf9), VUR(vf9), VUR(vf9y)
	vaddz.x		VUR(vf9), VUR(vf9), VUR(vf9z)
	vaddw.x		VUR(vf9), VUR(vf9), VUR(vf9w)
	#vrcp.s		VUR(vf9x), VUR(vf9x)
	vdiv		VUR(Q), VUR(vf0w), VUR(vf9x)
	vwaitq
	vmulq.x		VUR(vf9x), VUR(vf2x), VUR(Q)

	// Interpolate a/b, output point
	vsub.xyzw	VUR(vf14), VUR(vf4), VUR(vf10)			// (a-b)
	vsub.xyzw	VUR(vf15), VUR(vf5), VUR(vf11)			//
	vsub.xyzw	VUR(vf16), VUR(vf6), VUR(vf12)			//
	vsub.xyzw	VUR(vf17), VUR(vf7), VUR(vf13)			//

	#vmscl.q	M100, M100, VUR(vf9x)			// (a-b)*x
	vmulx.xyzw	VUR(vf14), VUR(vf14), VUR(vf9x)			// (a-b)*x
	vmulx.xyzw	VUR(vf15), VUR(vf15), VUR(vf9x)			//
	vmulx.xyzw	VUR(vf16), VUR(vf16), VUR(vf9x)			//
	vmulx.xyzw	VUR(vf17), VUR(vf17), VUR(vf9x)			//

	vadd.xyzw	VUR(vf14), VUR(vf10), VUR(vf14)			// b + (a-b)*x
	vadd.xyzw	VUR(vf15), VUR(vf11), VUR(vf15)			//
	sqc2		VUR(vf14), 0($a0)				// *out = *tmp
	vadd.xyzw	VUR(vf16), VUR(vf12), VUR(vf16)			//
	sqc2		VUR(vf15), 16($a0)
	vadd.xyzw	VUR(vf17), VUR(vf13), VUR(vf17)			//
	sqc2		VUR(vf16), 32($a0)
	addiu		$v0, $v0, 1					// outcout++
	sqc2		VUR(vf17), 48($a0)
	addiu		$a0, $a0, 64				// out++
	
a_is_inside_copy:
	
	sqc2		VUR(vf4), 0($a0)				// *out = *a
	sqc2		VUR(vf5), 16($a0)
	sqc2		VUR(vf6), 32($a0)
	sqc2		VUR(vf7), 48($a0)

	addiu		$a0, $a0, 64				// out++
	b			finished_vertex
	addiu		$v0, $v0, 1					// outcout++

a_is_outside:
	#vcmp.s		GT, VUR(vf2x), VUR(vf2x)[0]
	qmfc2		$t0, VUR(vf2)
	pextlw		$t0, $t0, $t0		//extend sign bit
	bgtz		$t0, finished_vertex			// bDotPlane <= 0 --> a_is_outside_copy
	nop
	
	// Calculate the parametric intersection point
	vsub.xyzw	VUR(vf8), VUR(vf11), VUR(vf5)			// VUR(vf8) = b.ProjectedPos - a.ProjectedPos
	#vdot.q		VUR(vf9x), VUR(vf8), VUR(vf1)			// VUR(vf9x) = dot( (b.ProjectedPos - a.ProjectedPos), plane )
	vmul.xyzw	VUR(vf9), VUR(vf8), VUR(vf1)
	vaddy.x		VUR(vf9), VUR(vf9), VUR(vf9y)
	vaddz.x		VUR(vf9), VUR(vf9), VUR(vf9z)
	vaddw.x		VUR(vf9), VUR(vf9), VUR(vf9w)
	#vrcp.s		VUR(vf9x), VUR(vf9x)
	vdiv		VUR(Q), VUR(vf0w), VUR(vf9x)
	vwaitq
	vmulq.x		VUR(vf9x), VUR(vf2x), VUR(Q)

	// Interpolate a/b, output point
	vsub.xyzw		VUR(vf14), VUR(vf4), VUR(vf10)			// (a-b)
	vsub.xyzw		VUR(vf15), VUR(vf5), VUR(vf11)			//
	vsub.xyzw		VUR(vf16), VUR(vf6), VUR(vf12)			//
	vsub.xyzw		VUR(vf17), VUR(vf7), VUR(vf13)			//

	#vmscl.q	M100, M100, VUR(vf9x)			// (a-b)*x
	vmulx.xyzw	VUR(vf14), VUR(vf14), VUR(vf9x)			// (a-b)*x
	vmulx.xyzw	VUR(vf15), VUR(vf15), VUR(vf9x)			//
	vmulx.xyzw	VUR(vf16), VUR(vf16), VUR(vf9x)			//
	vmulx.xyzw	VUR(vf17), VUR(vf17), VUR(vf9x)			//

	vadd.xyzw	VUR(vf14), VUR(vf10), VUR(vf14)			// b + (a-b)*x
	vadd.xyzw	VUR(vf15), VUR(vf11), VUR(vf15)			//
	sqc2		VUR(vf14), 0($a0)				// *out = *tmp
	vadd.xyzw	VUR(vf16), VUR(vf12), VUR(vf16)			//
	sqc2		VUR(vf15), 16($a0)
	vadd.xyzw	VUR(vf17), VUR(vf13), VUR(vf17)			//
	sqc2		VUR(vf16), 32($a0)
	addiu		$v0, $v0, 1					// outcout++
	sqc2		VUR(vf17), 48($a0)
	addiu		$a0, $a0, 64				// out++
	
finished_vertex:
	#vmmov.q		M300, M200					// b = lat_point
	vmove.xyzw	VUR(vf10), VUR(vf4)					// b = lat_point
	vmove.xyzw	VUR(vf11), VUR(vf5)
	vmove.xyzw	VUR(vf12), VUR(vf6)
	vmove.xyzw	VUR(vf13), VUR(vf7)
	vmove.x		VUR(vf2x), VUR(vf3x)					// move old aDotPlane as new bDotPlane

	addiu		$a3, $a3, -1				// verts_remaining--
	bne			$a3, $0, get_next_vertex	// verts_remaining != 0 --> get_next_vertex
	addiu		$a1, $a1, 64				// source++
	
finished_all_vertices:
	jr			$ra
	nop


	.set pop

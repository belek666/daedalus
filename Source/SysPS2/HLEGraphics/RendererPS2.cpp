#include "stdafx.h"
#include "RendererPS2.h"
#include "Core/ROM.h"
#include "Debug/Dump.h"
#include "Combiner/BlendConstant.h"
#include "Combiner/CombinerTree.h"
#include "Combiner/RenderSettings.h"
#include "Graphics/GraphicsContext.h"
#include "Graphics/NativeTexture.h"
#include "HLEGraphics/CachedTexture.h"
#include "HLEGraphics/DLDebug.h"
#include "HLEGraphics/RDPStateManager.h"
#include "HLEGraphics/TextureCache.h"
#include "Math/MathUtil.h"
#include "OSHLE/ultra_gbi.h"
#include "Utility/IO.h"
#include "Utility/Profiler.h"
#include "Utility/DaedalusTypes.h"
#include "SysPS2/GL.h"

#include <malloc.h>
#include <gsKit.h>
#include <libvux.h>
#include <kernel.h>
#include <gsInline.h>

#define ATST_NEVER		0
#define ATST_ALWAYS		1
#define ATST_LESS		2
#define ATST_LEQUAL		3
#define ATST_EQUAL		4
#define ATST_GEQUAL		5
#define ATST_GREATER	6
#define ATST_NOTEQUAL	7

#define ZTST_NEVER		0
#define ZTST_ALWAYS		1
#define ZTST_GEQUAL		2
#define ZTST_GREATER	3

extern GSGLOBAL* gsGlobal;
extern GSTEXTURE* CurrTex;
extern GSFONTM* gsFontM;

extern void gsKit_depth_mask(int mask);
extern void gsKit_scissor(int x0, int x1, int y0, int y1);
extern void gsKit_fog_color(u8 r, u8 g, u8 b);
extern void gsKit_fog(u8 f);
extern void gsKit_tex_wrap(int u, int v);

extern void InitBlenderMode(u32 blender);

BaseRenderer * gRenderer    = nullptr;
RendererPS2  * gRendererPS2 = nullptr;

#define GSZMAX 1048576.0f

static float coord_width = 300.0f;
static float coord_height = 300.0f;
static short coord_x = 640 / 2;
static short coord_y = 480 / 2;
static float coord_near = 1.0f;
static float coord_far = 65535.0f;
extern u32 gsZMax;

int gsShading = 0;
int gsBlend = GS_SETTING_OFF;
int gsFogEnable = 0;

static float toScreen(float z, float zmin, float zmax, float nearz, float farz) {
	float cz = (-zmax * nearz + zmin * farz) / (-nearz + farz);
	float az  = farz * nearz * (-zmin + zmax) / (-nearz + farz);
	return z * cz + az;
}

void gsViewport(int x, int y, int width, int height)
{
	gsGlobal->OffsetX = (int)((2048.0f - width / 2) * 16.0f);
	gsGlobal->OffsetY = (int)((2048.0f - height / 2) * 16.0f);

	u64* p_data;
	u64* p_store;

	p_data = p_store = (u64*)gsKit_heap_alloc(gsGlobal, 1, 16, GIF_AD);

	*p_data++ = GIF_TAG_AD(1);
	*p_data++ = GIF_AD;

	*p_data++ = GS_SETREG_XYOFFSET_1(gsGlobal->OffsetX, gsGlobal->OffsetY);
	*p_data++ = GS_XYOFFSET_1;

	coord_x = x + width / 2;
	coord_y = y + height / 2;
	coord_width = width / 2;
	coord_height = height / 2;
}

inline void gsDepthRange(float nearVal, float farVal)
{
	coord_near = farVal;
	coord_far = nearVal;
}

static float u_offset = 0.0f;
static float v_offset = 0.0f;
static float u_scale = 1.0f;
static float v_scale = 1.0f;

inline void gsTexOffset(float u, float v)
{
	u_offset = u;
	v_offset = v;
}

inline void gsTexScale(float u, float v)
{
	u_scale = u;
	v_scale = v;
}

static VU_MATRIX proj;

void sceGuSetMatrix(EGuMatrixType type, const ScePspFMatrix4* mtx)
{
	memcpy(&proj, mtx, sizeof(VU_MATRIX));
}

void gsTexEnvColor(int color)
{
	//TexEnvColor = GS_SETREG_RGBAQ(color & 0xFF, (color >> 8) & 0xFF, (color >> 16) & 0xFF, ((color >> 24) & 0xFF + 1) / 2, 0x00);
	//useTexEnvColor = true;

	//gsFog(0xFE, (color & 0xFF), ((color >> 8) & 0xFF), ((color >> 16) & 0xFF));
	//gsGlobal->PrimFogEnable = 1;
}

void sceGuFog(float near, float far, unsigned int color)
{
	printf("sceGuFog %f %f %08x\n", near, far, color);
}

#define GS_TFX_MODULATE 0  //modulate
#define GS_TFX_DECAL 1
#define GS_TFX_REPLACE 2  //decal
#define GS_TFX_ADD 3
#define GS_TFX_BLEND 4

#define GS_TCC_RGB 0
#define GS_TCC_RGBA 1

static int gstfunc = 0;
static int gstcc = 1;

void gsTexFunc(int func, int mode)
{
	//F * Cv + (0xFF - F) * Fc

	//printf("func %d\n", func);

	//gsGlobal->PrimFogEnable = 0;

	switch (func)
	{
		case GS_TFX_MODULATE:
		{
			gstfunc = 0; 
			gstcc = mode; 
			break;
		}
		case GS_TFX_DECAL:
		{
			if (mode == GS_TCC_RGB)
				gstfunc = 1;
			else
				gstfunc = 0; //Cv = Ct -> Cv = Cf * (1 - At) + Ct * At ?
			
			gstcc = mode;
			break;
		}
		case GS_TFX_REPLACE:
		{
			gstfunc = 1;
			gstcc = mode;
			break;
		}
		case GS_TFX_ADD:
		{
			gstfunc = 0; //Cv=Cf*Ct -> Cv=Cf+Ct ?
			gstcc = mode;
			//gsGlobal->PrimFogEnable = 1;
			break;
		}
		case GS_TFX_BLEND:
		{
			gstfunc = 0; // Cv=Ct*Cf -> Cv = (Cf * (1 - Ct)) + (Cc * Ct) ?
			//gsGlobal->PrimFogEnable = 1;
			gstcc = mode;
			break;
		}
	}
}

inline void gsDepthMask(int mask)
{
	//gsKit_depth_mask(mask);
}

static inline u32 lzw(u32 val)
{
	u32 res;
	__asm__ __volatile__("   plzcw   %0, %1    " : "=r" (res) : "r" (val));
	return(res);
}

static inline void gsKit_set_tw_th(const GSTEXTURE* Texture, int* tw, int* th)
{
	*tw = 31 - (lzw(Texture->Width) + 1);
	if (Texture->Width > (u32)(1 << *tw))
		(*tw)++;

	*th = 31 - (lzw(Texture->Height) + 1);
	if (Texture->Height > (u32)(1 << *th))
		(*th)++;
}

/// Textured Triangle Primitive GIFTAG
#define GIF_TAG_TRIANGLE_TEXTURED_Q(NLOOP)   \
		((u64)(NLOOP)		<< 0)	| \
		((u64)(1)		<< 15)	| \
		((u64)(0)		<< 46)	| \
		((u64)(0)		<< 47)	| \
		((u64)(1)		<< 58)	| \
		((u64)(10)		<< 60);
/// Textured Triangle Primitive REGLIST
#define GIF_TAG_TRIANGLE_TEXTURED_Q_REGS(ctx)   \
		((u64)(GS_TEX0_1 + ctx)	<< 0)	| \
		((u64)(GS_PRIM)		<< 4)	| \
		((u64)(GS_RGBAQ)	<< 8)	| \
		((u64)(GS_ST)		<< 12)	| \
		((u64)(GS_XYZ2)		<< 16)	| \
		((u64)(GS_ST)		<< 20)	| \
		((u64)(GS_XYZ2)		<< 24)	| \
		((u64)(GS_ST)		<< 28)	| \
		((u64)(GS_XYZ2)		<< 32)	| \
		((u64)(GIF_NOP)		<< 36);
// Textured Triangle Goraud Primitive
/// Textured Triangle Goraud Primitive GIFTAG
#define GIF_TAG_TRIANGLE_GORAUD_TEXTURED_Q(NLOOP)   \
		((u64)(NLOOP)		<< 0)	| \
		((u64)(1)		<< 15)	| \
		((u64)(0)		<< 46)	| \
		((u64)(0)		<< 47)	| \
		((u64)(1)		<< 58)	| \
		((u64)(12)		<< 60);
/// Textured Triangle Goraud Primitive REGLIST
#define GIF_TAG_TRIANGLE_GORAUD_TEXTURED_Q_REGS(ctx)   \
		((u64)(GS_TEX0_1 + ctx)	<< 0)	| \
		((u64)(GS_PRIM)		<< 4)	| \
		((u64)(GS_RGBAQ)	<< 8)	| \
		((u64)(GS_ST)		<< 12)	| \
		((u64)(GS_XYZF2)	<< 16)	| \
		((u64)(GS_RGBAQ)	<< 20)	| \
		((u64)(GS_ST)		<< 24)	| \
		((u64)(GS_XYZF2)	<< 28)	| \
		((u64)(GS_RGBAQ)	<< 32)	| \
		((u64)(GS_ST)		<< 36)	| \
		((u64)(GS_XYZF2)	<< 40)	| \
		((u64)(GIF_NOP)		<< 44);

#define GIF_TAG_TRIANGLE_GOURAUD_REGS_F   \
		((u64)(GS_PRIM)		<< 0)	| \
		((u64)(GS_RGBAQ)	<< 4)	| \
		((u64)(GS_XYZF2)	<< 8)	| \
		((u64)(GS_RGBAQ)	<< 12)	| \
		((u64)(GS_XYZF2)	<< 16)	| \
		((u64)(GS_RGBAQ)	<< 20)	| \
		((u64)(GS_XYZF2)	<< 24)	| \
		((u64)(GIF_NOP)		<< 28);

#define GS_SETREG_ST(s, t) ((u64)(s) | ((u64)(t) << 32))

void _gsKit_prim_sprite_texture_3d(GSGLOBAL* gsGlobal, const GSTEXTURE* Texture,
	float x1, float y1, int iz1, float u1, float v1,
	float x2, float y2, int iz2, float u2, float v2, u64 color)
{
	gsKit_set_texfilter(gsGlobal, Texture->Filter);

	u64* p_data;
	int qsize = 4;
	int bsize = 64;

	int tw, th;
	gsKit_set_tw_th(Texture, &tw, &th);

	int ix1 = gsKit_float_to_int_x(gsGlobal, x1);
	int ix2 = gsKit_float_to_int_x(gsGlobal, x2);
	int iy1 = gsKit_float_to_int_y(gsGlobal, y1);
	int iy2 = gsKit_float_to_int_y(gsGlobal, y2);

	int iu1 = gsKit_float_to_int_u(Texture, u1);
	int iu2 = gsKit_float_to_int_u(Texture, u2);
	int iv1 = gsKit_float_to_int_v(Texture, v1);
	int iv2 = gsKit_float_to_int_v(Texture, v2);

	p_data = (u64*)gsKit_heap_alloc(gsGlobal, qsize, bsize, GSKIT_GIF_PRIM_SPRITE_TEXTURED);

	*p_data++ = GIF_TAG_SPRITE_TEXTURED(0);
	*p_data++ = GIF_TAG_SPRITE_TEXTURED_REGS(gsGlobal->PrimContext);

	if (Texture->VramClut == 0)
	{
		*p_data++ = GS_SETREG_TEX0(Texture->Vram / 256, Texture->TBW, Texture->PSM,
			tw, th, gstcc, gstfunc,
			0, 0, 0, 0, GS_CLUT_STOREMODE_NOLOAD);
	}
	else
	{
		*p_data++ = GS_SETREG_TEX0(Texture->Vram / 256, Texture->TBW, Texture->PSM,
			tw, th, gstcc, gstfunc,
			Texture->VramClut / 256, Texture->ClutPSM, 0, 0, GS_CLUT_STOREMODE_LOAD);
	}

	*p_data++ = GS_SETREG_PRIM(GS_PRIM_PRIM_SPRITE, 0, 1, gsGlobal->PrimFogEnable,
		gsBlend, gsGlobal->PrimAAEnable,
		1, gsGlobal->PrimContext, 0);

	*p_data++ = color;

	*p_data++ = GS_SETREG_UV(iu1, iv1);
	*p_data++ = GS_SETREG_XYZ2(ix1, iy1, iz1);

	*p_data++ = GS_SETREG_UV(iu2, iv2);
	*p_data++ = GS_SETREG_XYZ2(ix2, iy2, iz2);
}

void _gsKit_prim_triangle_goraud_texture_3d(GSGLOBAL* gsGlobal, GSTEXTURE* Texture,
	float x1, float y1, int iz1, float u1, float v1,
	float x2, float y2, int iz2, float u2, float v2,
	float x3, float y3, int iz3, float u3, float v3,
	u64 color1, u64 color2, u64 color3, u8 fog1, u8 fog2, u8 fog3)
{
	gsKit_set_texfilter(gsGlobal, Texture->Filter);
	u64* p_data;
	int qsize = 6;
	int bsize = 96;

	int tw, th;
	gsKit_set_tw_th(Texture, &tw, &th);

	int ix1 = (int)(x1 * 16.0f) + gsGlobal->OffsetX;
	int ix2 = (int)(x2 * 16.0f) + gsGlobal->OffsetX;
	int ix3 = (int)(x3 * 16.0f) + gsGlobal->OffsetX;
	int iy1 = (int)(y1 * 16.0f) + gsGlobal->OffsetY;
	int iy2 = (int)(y2 * 16.0f) + gsGlobal->OffsetY;
	int iy3 = (int)(y3 * 16.0f) + gsGlobal->OffsetY;

	int xymax = (int)(4095.9375f * 16.0f);
	//int zmax = (gsZMax - 0xFF) / 2;

	if (ix1 > xymax || ix1 < 0 || ix2 > xymax || ix2 < 0 || ix3 > xymax || ix3 < 0)
		return;

	if (iy1 > xymax || iy1 < 0 || iy2 > xymax || iy2 < 0 || iy3 > xymax || iy3 < 0)
		return;

	//if (iz1 > zmax || iz1 < -zmax || iz2 > zmax || iz2 < -zmax || iz3 > zmax || iz3 < -zmax)
	//	return;

	REG32 s1, s2, s3, t1, t2, t3;

	s1._f32 = u1;
	s2._f32 = u2;
	s3._f32 = u3;

	t1._f32 = v1;
	t2._f32 = v2;
	t3._f32 = v3;

	p_data = (u64 *)gsKit_heap_alloc(gsGlobal, qsize, bsize, GSKIT_GIF_PRIM_TRIANGLE_TEXTURED);

	*p_data++ = GIF_TAG_TRIANGLE_GORAUD_TEXTURED_Q(0);
	*p_data++ = GIF_TAG_TRIANGLE_GORAUD_TEXTURED_Q_REGS(gsGlobal->PrimContext);

	if (Texture->VramClut == 0)
	{
		*p_data++ = GS_SETREG_TEX0(Texture->Vram / 256, Texture->TBW, Texture->PSM,
			tw, th, gstcc, gstfunc,
			0, 0, 0, 0, GS_CLUT_STOREMODE_NOLOAD);
	}
	else
	{
		*p_data++ = GS_SETREG_TEX0(Texture->Vram / 256, Texture->TBW, Texture->PSM,
			tw, th, gstcc, gstfunc,
			Texture->VramClut / 256, Texture->ClutPSM, 0, 0, GS_CLUT_STOREMODE_LOAD);
	}

	*p_data++ = GS_SETREG_PRIM(GS_PRIM_PRIM_TRIANGLE, gsShading, 1, gsFogEnable,
		gsBlend, gsGlobal->PrimAAEnable,
		0, gsGlobal->PrimContext, 0);


	*p_data++ = color1;
	*p_data++ = GS_SETREG_ST(s1._u32, t1._u32);
	*p_data++ = GS_SETREG_XYZF2(ix1, iy1, iz1, fog1);

	*p_data++ = color2;
	*p_data++ = GS_SETREG_ST(s2._u32, t2._u32);
	*p_data++ = GS_SETREG_XYZF2(ix2, iy2, iz2, fog2);

	*p_data++ = color3;
	*p_data++ = GS_SETREG_ST(s3._u32, t3._u32);
	*p_data++ = GS_SETREG_XYZF2(ix3, iy3, iz3, fog3);
}


void _gsKit_prim_triangle_gouraud_3d(GSGLOBAL* gsGlobal, float x1, float y1, int iz1,
	float x2, float y2, int iz2,
	float x3, float y3, int iz3,
	u64 color1, u64 color2, u64 color3, u8 fog1, u8 fog2, u8 fog3)
{
	u64* p_store;
	u64* p_data;
	int qsize = 4;
	int bsize = 64;

	int ix1 = (int)(x1 * 16.0f) + gsGlobal->OffsetX;
	int ix2 = (int)(x2 * 16.0f) + gsGlobal->OffsetX;
	int ix3 = (int)(x3 * 16.0f) + gsGlobal->OffsetX;
	int iy1 = (int)(y1 * 16.0f) + gsGlobal->OffsetY;
	int iy2 = (int)(y2 * 16.0f) + gsGlobal->OffsetY;
	int iy3 = (int)(y3 * 16.0f) + gsGlobal->OffsetY;

	int xymax = (int)(4095.9375f * 16.0f);
	//int zmax = (gsZMax - 0xFF) / 2;

	if (ix1 > xymax || ix1 < 0 || ix2 > xymax || ix2 < 0 || ix3 > xymax || ix3 < 0)
		return;

	if (iy1 > xymax || iy1 < 0 || iy2 > xymax || iy2 < 0 || iy3 > xymax || iy3 < 0)
		return;

	//if (iz1 > zmax || iz1 < -zmax || iz2 > zmax || iz2 < -zmax || iz3 > zmax || iz3 < -zmax)
	//	return;

	p_store = p_data = (u64*)gsKit_heap_alloc(gsGlobal, qsize, bsize, GSKIT_GIF_PRIM_TRIANGLE_GOURAUD);

	if (p_store == gsGlobal->CurQueue->last_tag)
	{
		*p_data++ = GIF_TAG_TRIANGLE_GOURAUD(0);
		*p_data++ = GIF_TAG_TRIANGLE_GOURAUD_REGS_F;
	}

	*p_data++ = GS_SETREG_PRIM(GS_PRIM_PRIM_TRIANGLE, gsShading, 0, gsFogEnable,
		gsBlend, gsGlobal->PrimAAEnable,
		0, gsGlobal->PrimContext, 0);

	*p_data++ = color1;
	*p_data++ = GS_SETREG_XYZF2(ix1, iy1, iz1, fog1);

	*p_data++ = color2;
	*p_data++ = GS_SETREG_XYZF2(ix2, iy2, iz2, fog2);

	*p_data++ = color3;
	*p_data++ = GS_SETREG_XYZF2(ix3, iy3, iz3, fog3);
}

void _gsKit_prim_triangle_strip_texture_3d(GSGLOBAL* gsGlobal, GSTEXTURE* Texture,
	float* TriStrip, int segments, u64 color)
{
	gsKit_set_texfilter(gsGlobal, Texture->Filter);
	u64* p_data;
	int qsize = 3 + (segments * 2);
	int count;
	int vertexdata[segments * 5];

	int tw, th;
	gsKit_set_tw_th(Texture, &tw, &th);

	for (count = 0; count < (segments * 5); count += 5)
	{
		vertexdata[count + 0] = gsKit_float_to_int_x(gsGlobal, *TriStrip++);
		vertexdata[count + 1] = gsKit_float_to_int_y(gsGlobal, *TriStrip++);
		vertexdata[count + 2] = (int)((*TriStrip++) * 16.0f); // z
		vertexdata[count + 3] = gsKit_float_to_int_u(Texture, *TriStrip++);
		vertexdata[count + 4] = gsKit_float_to_int_v(Texture, *TriStrip++);
	}

	p_data = (u64*)gsKit_heap_alloc(gsGlobal, qsize, (qsize * 16), GIF_AD);

	*p_data++ = GIF_TAG_AD(qsize);
	*p_data++ = GIF_AD;

	if (Texture->VramClut == 0)
	{
		*p_data++ = GS_SETREG_TEX0(Texture->Vram / 256, Texture->TBW, Texture->PSM,
			tw, th, gstcc, gstfunc,
			0, 0, 0, 0, GS_CLUT_STOREMODE_NOLOAD);
	}
	else
	{
		*p_data++ = GS_SETREG_TEX0(Texture->Vram / 256, Texture->TBW, Texture->PSM,
			tw, th, gstcc, gstfunc,
			Texture->VramClut / 256, Texture->ClutPSM, 0, 0, GS_CLUT_STOREMODE_LOAD);
	}
	*p_data++ = GS_TEX0_1 + gsGlobal->PrimContext;

	*p_data++ = GS_SETREG_PRIM(GS_PRIM_PRIM_TRISTRIP, 0, 1, gsGlobal->PrimFogEnable,
		gsBlend, gsGlobal->PrimAAEnable,
		1, gsGlobal->PrimContext, 0);

	*p_data++ = GS_PRIM;

	*p_data++ = color;
	*p_data++ = GS_RGBAQ;

	for (count = 0; count < (segments * 5); count += 5)
	{
		*p_data++ = GS_SETREG_UV(vertexdata[count + 3], vertexdata[count + 4]);
		*p_data++ = GS_UV;

		*p_data++ = GS_SETREG_XYZ2(vertexdata[count], vertexdata[count + 1], vertexdata[count + 2]);
		*p_data++ = GS_XYZ2;
	}
}

#define GS_X(v)		(v.x * coord_width / v.w + coord_x)
#define GS_Y(v)		(-v.y * coord_height / v.w + coord_y)
#define GS_Z(v)		(int)(v.z / v.w)

#define GS_U(u)		((u + u_offset) * u_scale)
#define GS_V(v)		((v + v_offset) * v_scale)

void DrawPrims(DaedalusVtx* p_vertices, u32 num_vertices, u32 prim_type, bool textured)
{
	VU_VECTOR in_vect[3];
	VU_VECTOR out_vect[3];
	float u[3];
	float v[3];
	u64 color[3];
	u8 fog[3];

	if (prim_type == GS_PRIM_PRIM_SPRITE)
	{
		for (u32 i = 0; i < num_vertices; i += 2)
		{
			if (textured)
			{
				_gsKit_prim_sprite_texture_3d(gsGlobal, CurrTex, 
					p_vertices[i + 0].Position.x,
					p_vertices[i + 0].Position.y,
					(int)p_vertices[i + 0].Position.z,
					p_vertices[i + 0].Texture.x,  // U1
					p_vertices[i + 0].Texture.y,  // V1
					p_vertices[i + 1].Position.x,
					p_vertices[i + 1].Position.y,
					(int)p_vertices[i + 1].Position.z,
					p_vertices[i + 1].Texture.x, // U2
					p_vertices[i + 1].Texture.y, // V2
					GS_SETREG_RGBAQ(p_vertices[i + 0].Colour.GetR(), p_vertices[i + 0].Colour.GetG(), p_vertices[i + 0].Colour.GetB(), (p_vertices[i + 0].Colour.GetA()) / 2, 0x00));
			}
			else
			{
				gsKit_prim_sprite(gsGlobal, 
					p_vertices[i + 0].Position.x,
					p_vertices[i + 0].Position.y,
					p_vertices[i + 1].Position.x,
					p_vertices[i + 1].Position.y,
					(int)p_vertices[i + 0].Position.z,
					GS_SETREG_RGBAQ(p_vertices[i + 0].Colour.GetR(), p_vertices[i + 0].Colour.GetG(), p_vertices[i + 0].Colour.GetB(), (p_vertices[i + 0].Colour.GetA()) / 2, 0x00));
			}
		}
	}
	else if (prim_type == GS_PRIM_PRIM_TRIANGLE)
	{
		for (u32 i = 0; i < num_vertices; i += 3)
		{
			in_vect[0].x = p_vertices[i + 0].Position.x;
			in_vect[0].y = p_vertices[i + 0].Position.y;
			in_vect[0].z = p_vertices[i + 0].Position.z;
			in_vect[0].w = 1.0f;

			in_vect[1].x = p_vertices[i + 1].Position.x;
			in_vect[1].y = p_vertices[i + 1].Position.y;
			in_vect[1].z = p_vertices[i + 1].Position.z;
			in_vect[1].w = 1.0f;

			in_vect[2].x = p_vertices[i + 2].Position.x;
			in_vect[2].y = p_vertices[i + 2].Position.y;
			in_vect[2].z = p_vertices[i + 2].Position.z;
			in_vect[2].w = 1.0f;

			Vu0ApplyMatrix(&proj, &in_vect[0], &out_vect[0]);
			Vu0ApplyMatrix(&proj, &in_vect[1], &out_vect[1]);
			Vu0ApplyMatrix(&proj, &in_vect[2], &out_vect[2]);

			REG32 q1, q2, q3;

			q1._f32 = 1.0f;
			q2._f32 = 1.0f;
			q3._f32 = 1.0f;

			if (out_vect[0].w != 0 && out_vect[1].w != 0 && out_vect[2].w != 0)
			{
				q1._f32 /= out_vect[0].w;
				q2._f32 /= out_vect[1].w;
				q3._f32 /= out_vect[2].w;
			}

			color[0] = GS_SETREG_RGBAQ((p_vertices[i + 0].Colour.GetR() + 1) / 2, 
				(p_vertices[i + 0].Colour.GetG() + 1) / 2, 
				(p_vertices[i + 0].Colour.GetB() + 1) / 2, 
				(p_vertices[i + 0].Colour.GetA() + 1) / 2, q1._u32);
			color[1] = GS_SETREG_RGBAQ((p_vertices[i + 1].Colour.GetR() + 1) / 2, 
				(p_vertices[i + 1].Colour.GetG() + 1) / 2, 
				(p_vertices[i + 1].Colour.GetB() + 1) / 2, 
				(p_vertices[i + 1].Colour.GetA() + 1) / 2, q2._u32);
			color[2] = GS_SETREG_RGBAQ((p_vertices[i + 2].Colour.GetR() + 1) / 2, 
				(p_vertices[i + 2].Colour.GetG() + 1) / 2, 
				(p_vertices[i + 2].Colour.GetB() + 1) / 2, 
				(p_vertices[i + 2].Colour.GetA() + 1) / 2, q3._u32);
			fog[0] = p_vertices[i + 0].Colour.GetA();
			fog[1] = p_vertices[i + 1].Colour.GetA();
			fog[2] = p_vertices[i + 2].Colour.GetA();
#if 0
			//color[2] = color[1] = color[0] = GS_SETREG_RGBAQ(0xFF, 0, 0, 0x80, 1);

			gsKit_prim_line_3d(gsGlobal, GS_X(out_vect[0]), GS_Y(out_vect[0]), GS_Z(out_vect[0]), GS_X(out_vect[1]), GS_Y(out_vect[1]), GS_Z(out_vect[1]), color[0]);
			gsKit_prim_line_3d(gsGlobal, GS_X(out_vect[1]), GS_Y(out_vect[1]), GS_Z(out_vect[1]), GS_X(out_vect[2]), GS_Y(out_vect[2]), GS_Z(out_vect[2]), color[1]);
			gsKit_prim_line_3d(gsGlobal, GS_X(out_vect[2]), GS_Y(out_vect[2]), GS_Z(out_vect[2]), GS_X(out_vect[0]), GS_Y(out_vect[0]), GS_Z(out_vect[0]), color[2]);
#else

			out_vect[0].z = toScreen(out_vect[0].z, 1.0f, 16777215.0f, coord_near, coord_far);
			out_vect[1].z = toScreen(out_vect[1].z, 1.0f, 16777215.0f, coord_near, coord_far);
			out_vect[2].z = toScreen(out_vect[2].z, 1.0f, 16777215.0f, coord_near, coord_far);

			if (textured)
			{
				u[0] = GS_U(p_vertices[i + 0].Texture.x) * q1._f32;
				u[1] = GS_U(p_vertices[i + 1].Texture.x) * q2._f32;
				u[2] = GS_U(p_vertices[i + 2].Texture.x) * q3._f32;

				v[0] = GS_V(p_vertices[i + 0].Texture.y) * q1._f32;
				v[1] = GS_V(p_vertices[i + 1].Texture.y) * q2._f32;
				v[2] = GS_V(p_vertices[i + 2].Texture.y) * q3._f32;

				_gsKit_prim_triangle_goraud_texture_3d(gsGlobal, CurrTex,
					GS_X(out_vect[0]), GS_Y(out_vect[0]), GS_Z(out_vect[0]),
					u[0], v[0],
					GS_X(out_vect[1]), GS_Y(out_vect[1]), GS_Z(out_vect[1]),
					u[1], v[1],
					GS_X(out_vect[2]), GS_Y(out_vect[2]), GS_Z(out_vect[2]),
					u[2], v[2],
					color[0], color[1], color[2], 
					fog[0], fog[1], fog[2] );
			}
			else
			{
				_gsKit_prim_triangle_gouraud_3d(gsGlobal,
					GS_X(out_vect[0]), GS_Y(out_vect[0]), GS_Z(out_vect[0]),
					GS_X(out_vect[1]), GS_Y(out_vect[1]), GS_Z(out_vect[1]),
					GS_X(out_vect[2]), GS_Y(out_vect[2]), GS_Z(out_vect[2]),
					color[0],
					color[1],
					color[2], fog[0], fog[1], fog[2]);
			}
#endif
		}
	}
	else if (prim_type == GS_PRIM_PRIM_TRISTRIP)
	{
		float* tris = (float*)memalign(128, sizeof(float) * num_vertices * 5);

		if (textured)
		{
			for (u32 i = 0; i < num_vertices; i++)
			{
				tris[i * 5 + 0] = p_vertices[i].Position.x;
				tris[i * 5 + 1] = p_vertices[i].Position.y;
				tris[i * 5 + 2] = p_vertices[i].Position.z;
				tris[i * 5 + 3] = p_vertices[i].Texture.x;
				tris[i * 5 + 4] = p_vertices[i].Texture.y;
			}

			_gsKit_prim_triangle_strip_texture_3d(gsGlobal, CurrTex,
				tris, num_vertices, GS_SETREG_RGBAQ(p_vertices[0].Colour.GetR(), p_vertices[0].Colour.GetG(), p_vertices[0].Colour.GetB(), (p_vertices[0].Colour.GetA()) / 2, 0x00));
		}
		else
		{
			for (u32 i = 0; i < num_vertices; i++)
			{
				tris[i * 3 + 0] = p_vertices[i].Position.x;
				tris[i * 3 + 1] = p_vertices[i].Position.y;
				tris[i * 3 + 2] = p_vertices[i].Position.z;
			}

			gsKit_prim_triangle_strip_3d(gsGlobal, tris, num_vertices, GS_SETREG_RGBAQ(p_vertices[0].Colour.GetR(), p_vertices[0].Colour.GetG(), p_vertices[0].Colour.GetB(), (p_vertices[0].Colour.GetA()) / 2, 0x00));
		}

		free(tris);
	}
}

#ifdef DAEDALUS_DEBUG_DISPLAYLIST

// General blender used for Blend Explorer when debuging Dlists //Corn
DebugBlendSettings gDBlend;

static const u32 kPlaceholderTextureWidth = 16;
static const u32 kPlaceholderTextureHeight = 16;
static const u32 kPlaceholderSize = kPlaceholderTextureWidth * kPlaceholderTextureHeight;

ALIGNED_GLOBAL(u32, gWhiteTexture[kPlaceholderSize], DATA_ALIGN);
ALIGNED_GLOBAL(u32, gPlaceholderTexture[kPlaceholderSize], DATA_ALIGN);
ALIGNED_GLOBAL(u32, gSelectedTexture[kPlaceholderSize], DATA_ALIGN);


#define BLEND_MODE_MAKER \
{ \
	const u32 PSPtxtFunc[5] = \
	{ \
		GS_TFX_MODULATE, \
		GS_TFX_BLEND, \
		GS_TFX_ADD, \
		GS_TFX_REPLACE, \
		GS_TFX_DECAL \
	}; \
	const u32 PSPtxtA[2] = \
	{ \
		GS_TCC_RGB, \
		GS_TCC_RGBA \
	}; \
	switch( gDBlend.ForceRGB ) \
	{ \
		case 1: details.ColourAdjuster.SetRGB( c32::White ); break; \
		case 2: details.ColourAdjuster.SetRGB( c32::Black ); break; \
		case 3: details.ColourAdjuster.SetRGB( c32::Red ); break; \
		case 4: details.ColourAdjuster.SetRGB( c32::Green ); break; \
		case 5: details.ColourAdjuster.SetRGB( c32::Blue ); break; \
		case 6: details.ColourAdjuster.SetRGB( c32::Magenta ); break; \
		case 7: details.ColourAdjuster.SetRGB( c32::Gold ); break; \
	} \
	switch( gDBlend.SetRGB ) \
	{ \
		case 1: details.ColourAdjuster.SetRGB( details.PrimColour ); break; \
		case 2: details.ColourAdjuster.SetRGB( details.PrimColour.ReplicateAlpha() ); break; \
		case 3: details.ColourAdjuster.SetRGB( details.EnvColour ); break; \
		case 4: details.ColourAdjuster.SetRGB( details.EnvColour.ReplicateAlpha() ); break; \
	} \
	switch( gDBlend.SetA ) \
	{ \
		case 1: details.ColourAdjuster.SetA( details.PrimColour ); break; \
		case 2: details.ColourAdjuster.SetA( details.PrimColour.ReplicateAlpha() ); break; \
		case 3: details.ColourAdjuster.SetA( details.EnvColour ); break; \
		case 4: details.ColourAdjuster.SetA( details.EnvColour.ReplicateAlpha() ); break; \
	} \
	switch( gDBlend.SetRGBA ) \
	{ \
		case 1: details.ColourAdjuster.SetRGBA( details.PrimColour ); break; \
		case 2: details.ColourAdjuster.SetRGBA( details.PrimColour.ReplicateAlpha() ); break; \
		case 3: details.ColourAdjuster.SetRGBA( details.EnvColour ); break; \
		case 4: details.ColourAdjuster.SetRGBA( details.EnvColour.ReplicateAlpha() ); break; \
	} \
	switch( gDBlend.ModRGB ) \
	{ \
		case 1: details.ColourAdjuster.ModulateRGB( details.PrimColour ); break; \
		case 2: details.ColourAdjuster.ModulateRGB( details.PrimColour.ReplicateAlpha() ); break; \
		case 3: details.ColourAdjuster.ModulateRGB( details.EnvColour ); break; \
		case 4: details.ColourAdjuster.ModulateRGB( details.EnvColour.ReplicateAlpha() ); break; \
	} \
	switch( gDBlend.ModA ) \
	{ \
		case 1: details.ColourAdjuster.ModulateA( details.PrimColour ); break; \
		case 2: details.ColourAdjuster.ModulateA( details.PrimColour.ReplicateAlpha() ); break; \
		case 3: details.ColourAdjuster.ModulateA( details.EnvColour ); break; \
		case 4: details.ColourAdjuster.ModulateA( details.EnvColour.ReplicateAlpha() ); break; \
	} \
	switch( gDBlend.ModRGBA ) \
	{ \
		case 1: details.ColourAdjuster.ModulateRGBA( details.PrimColour ); break; \
		case 2: details.ColourAdjuster.ModulateRGBA( details.PrimColour.ReplicateAlpha() ); break; \
		case 3: details.ColourAdjuster.ModulateRGBA( details.EnvColour ); break; \
		case 4: details.ColourAdjuster.ModulateRGBA( details.EnvColour.ReplicateAlpha() ); break; \
	} \
	switch( gDBlend.SubRGB ) \
	{ \
		case 1: details.ColourAdjuster.SubtractRGB( details.PrimColour ); break; \
		case 2: details.ColourAdjuster.SubtractRGB( details.PrimColour.ReplicateAlpha() ); break; \
		case 3: details.ColourAdjuster.SubtractRGB( details.EnvColour ); break; \
		case 4: details.ColourAdjuster.SubtractRGB( details.EnvColour.ReplicateAlpha() ); break; \
	} \
	switch( gDBlend.SubA ) \
	{ \
		case 1: details.ColourAdjuster.SubtractA( details.PrimColour ); break; \
		case 2: details.ColourAdjuster.SubtractA( details.PrimColour.ReplicateAlpha() ); break; \
		case 3: details.ColourAdjuster.SubtractA( details.EnvColour ); break; \
		case 4: details.ColourAdjuster.SubtractA( details.EnvColour.ReplicateAlpha() ); break; \
	} \
	switch( gDBlend.SubRGBA ) \
	{ \
		case 1: details.ColourAdjuster.SubtractRGBA( details.PrimColour ); break; \
		case 2: details.ColourAdjuster.SubtractRGBA( details.PrimColour.ReplicateAlpha() ); break; \
		case 3: details.ColourAdjuster.SubtractRGBA( details.EnvColour ); break; \
		case 4: details.ColourAdjuster.SubtractRGBA( details.EnvColour.ReplicateAlpha() ); break; \
	} \
	if( gDBlend.AOpaque ) details.ColourAdjuster.SetAOpaque(); \
	switch( gDBlend.sceENV ) \
	{ \
		case 1: gsTexEnvColor( details.EnvColour.GetColour() ); break; \
		case 2: gsTexEnvColor( details.PrimColour.GetColour() ); break; \
	} \
	details.InstallTexture = gDBlend.TexInstall; \
	gsTexFunc( PSPtxtFunc[ (gDBlend.TXTFUNC >> 1) % 6 ], PSPtxtA[ gDBlend.TXTFUNC & 1 ] ); \
}

#endif // DAEDALUS_DEBUG_DISPLAYLIST

RendererPS2::RendererPS2()
{
	//
//	Set up RGB = T0, A = T0
//
	mCopyBlendStates = new CBlendStates;
	{
		CAlphaRenderSettings* alpha_settings(new CAlphaRenderSettings("Copy"));
		CRenderSettingsModulate* colour_settings(new CRenderSettingsModulate("Copy"));

		alpha_settings->AddTermTexel0();
		colour_settings->AddTermTexel0();

		mCopyBlendStates->SetAlphaSettings(alpha_settings);
		mCopyBlendStates->AddColourSettings(colour_settings);
	}

	//
	//	Set up RGB = Diffuse, A = Diffuse
	//
	mFillBlendStates = new CBlendStates;
	{
		CAlphaRenderSettings* alpha_settings(new CAlphaRenderSettings("Fill"));
		CRenderSettingsModulate* colour_settings(new CRenderSettingsModulate("Fill"));

		alpha_settings->AddTermConstant(new CBlendConstantExpressionValue(BC_SHADE));
		colour_settings->AddTermConstant(new CBlendConstantExpressionValue(BC_SHADE));

		mFillBlendStates->SetAlphaSettings(alpha_settings);
		mFillBlendStates->AddColourSettings(colour_settings);
	}

#ifdef DAEDALUS_DEBUG_DISPLAYLIST
	memset(gWhiteTexture, 0xff, sizeof(gWhiteTexture));

	memset(&gDBlend.TexInstall, 0, sizeof(gDBlend));
	gDBlend.TexInstall = 1;

	u32	texel_idx = 0;
	const u32	COL_MAGENTA = c32::Magenta.GetColour();
	const u32	COL_GREEN = c32::Green.GetColour();
	const u32	COL_BLACK = c32::Black.GetColour();
	for (u32 y = 0; y < kPlaceholderTextureHeight; ++y)
	{
		for (u32 x = 0; x < kPlaceholderTextureWidth; ++x)
		{
			gPlaceholderTexture[texel_idx] = ((x & 1) == (y & 1)) ? COL_MAGENTA : COL_BLACK;
			gSelectedTexture[texel_idx] = ((x & 1) == (y & 1)) ? COL_GREEN : COL_BLACK;

			texel_idx++;
		}
	}
#endif
}

RendererPS2::~RendererPS2()
{
	delete mFillBlendStates;
	delete mCopyBlendStates;
}

void RendererPS2::RestoreRenderStates()
{
	//printf("RendererPS2:: %s \n", __func__);
	
	gsFogEnable = GS_SETTING_OFF;
	gsShading = 1;

	gsTexEnvColor(c32::White.GetColour());

	//gsKit_set_primalpha(gsGlobal, GS_SETREG_ALPHA(0, 1, 0, 1, 0), 0);

	gsDepthMask(1);

	gsBlend = GS_SETTING_OFF;

	gsGlobal->Test->ATST = ATST_GEQUAL;
	gsGlobal->Test->AREF = 0x04;
	//gsGlobal->Test->AREF = 0x80;
	gsGlobal->Test->AFAIL = 0;
	gsKit_set_test(gsGlobal, GS_ATEST_ON);
	
	gsKit_set_test(gsGlobal, GS_ZTEST_ON);

	gsTexFunc(GS_TFX_REPLACE, GS_TCC_RGB);
	gsKit_tex_wrap(GU_REPEAT, GU_REPEAT);

	gsTexOffset(0.0f, 0.0f);
	gsTexScale(1.0f, 1.0f);
}

RendererPS2::SBlendStateEntry RendererPS2::LookupBlendState(u64 mux, bool two_cycles)
{
#ifdef DAEDALUS_DEBUG_DISPLAYLIST
	DAEDALUS_PROFILE("RendererPSP::LookupBlendState");
	mRecordedCombinerStates.insert(mux);
#endif

	REG64 key;
	key._u64 = mux;

	// Top 8 bits are never set - use the very top one to differentiate between 1/2 cycles
	key._u32_1 |= (two_cycles << 31);

	BlendStatesMap::const_iterator	it(mBlendStatesMap.find(key._u64));
	if (it != mBlendStatesMap.end())
	{
		return it->second;
	}

	// Blendmodes with Inexact blends either get an Override blend or a Default blend (GU_TFX_MODULATE)
	// If its not an Inexact blend then we check if we need to Force a blend mode none the less// Salvy
	//
	SBlendStateEntry entry;
	CCombinerTree tree(mux, two_cycles);
	entry.States = tree.GetBlendStates();

	if (entry.States->IsInexact())
	{
		entry.OverrideFunction = LookupOverrideBlendModeInexact(mux);
	}
	else
	{
		// This is for non-inexact blends, errg hacks and such to be more precise
		entry.OverrideFunction = LookupOverrideBlendModeForced(mux);
	}

#ifdef DAEDALUS_DEBUG_DISPLAYLIST
	printf("Adding %08x%08x - %d cycles - %s\n", u32(mux >> 32), u32(mux), two_cycles ? 2 : 1, entry.States->IsInexact() ? IsCombinerStateDefault(mux) ? "Inexact(Default)" : "Inexact(Override)" : entry.OverrideFunction == nullptr ? "Auto" : "Forced");
#endif

	//Add blend mode to the Blend States Map
	mBlendStatesMap[key._u64] = entry;

	return entry;
}

#ifdef DAEDALUS_DEBUG_DISPLAYLIST
void RendererPS2::ResetDebugState()
{

}
#endif

void RendererPS2::RenderTriangles(DaedalusVtx* p_vertices, u32 num_vertices, bool disable_zbuffer)
{
	if (mTnL.Flags.Texture)
	{
		UpdateTileSnapshots(mTextureTile);

		const CNativeTexture* texture = mBoundTexture[0];

		if (texture && (mTnL.Flags._u32 & (TNL_LIGHT | TNL_TEXGEN)) != (TNL_LIGHT | TNL_TEXGEN))
		{
			float scale_x = texture->GetScaleX();
			float scale_y = texture->GetScaleY();

			// Hack to fix the sun in Zelda OOT/MM
			if (g_ROM.ZELDA_HACK && (gRDPOtherMode.L == 0x0c184241))	 //&& ti.GetFormat() == G_IM_FMT_I && (ti.GetWidth() == 64)
			{
				scale_x *= 0.5f;
				scale_y *= 0.5f;
			}
			gsTexOffset(-mTileTopLeft[0].s * scale_x / 4.f, -mTileTopLeft[0].t * scale_y / 4.f);
			gsTexScale(scale_x, scale_y);
		}
		else
		{
			gsTexOffset(0.0f, 0.0f);
			gsTexScale(1.0f, 1.0f);
		}
	}

	RenderUsingCurrentBlendMode(p_vertices, num_vertices, GS_PRIM_PRIM_TRIANGLE, 0, disable_zbuffer);
}

inline void RendererPS2::RenderFog( DaedalusVtx * p_vertices, u32 num_vertices, u32 triangle_mode, u32 render_flags )
{
	//This will render a second pass on triangles that are fog enabled to blend in the fog color as a function of depth(alpha) //Corn
	//
	//if( gRDPOtherMode.c1_m1a==3 || gRDPOtherMode.c1_m2a==3 || gRDPOtherMode.c2_m1a==3 || gRDPOtherMode.c2_m2a==3 )
	{
		printf("RendererPS2::RenderFog\n");
		//sceGuShadeModel(GU_SMOOTH);

		//sceGuDepthFunc(GU_EQUAL);	//Make sure to only blend on pixels that has been rendered on first pass //Corn
		//sceGuDepthMask(GL_TRUE);	//GL_TRUE to disable z-writes, no need to write to zbuffer for second pass //Corn
		//sceGuEnable(GU_BLEND);
		//sceGuDisable(GU_TEXTURE_2D);	//Blend triangle without a texture
		//sceGuDisable(GU_ALPHA_TEST);
		//sceGuBlendFunc(GU_ADD, GU_SRC_ALPHA, GU_ONE_MINUS_SRC_ALPHA, 0, 0);

		gsDepthMask(1);
		gsKit_set_test(gsGlobal, GS_ZTEST_ON);
		gsBlend = GS_SETTING_ON;
		gsKit_set_test(gsGlobal, GS_ATEST_OFF);
		gsKit_set_primalpha(gsGlobal, GS_SETREG_ALPHA(0, 1, 0, 1, 128), 0);

		u32 FogColor = mFogColour.GetColour();

		//Copy fog color to vertices
		for (u32 i = 0; i < num_vertices; i++)
		{
			u32 alpha = p_vertices[i].Colour.GetColour() & 0xFF000000;
			p_vertices[i].Colour = (c32)(alpha | FogColor);
		}

		//sceGuDrawArray(triangle_mode, render_flags, num_vertices, nullptr, p_vertices);
		
		DrawPrims(p_vertices, num_vertices, triangle_mode, false);

		//sceGuDepthFunc(GU_GEQUAL);	//Restore default depth function
	}
}

void RendererPS2::RenderUsingCurrentBlendMode( DaedalusVtx * p_vertices, u32 num_vertices, u32 triangle_mode, u32 render_mode, bool disable_zbuffer )
{
	static bool	ZFightingEnabled = false;

	//DAEDALUS_PROFILE("RendererPS2::RenderUsingCurrentBlendMode");

	if (disable_zbuffer)
	{
		//sceGuDisable(GU_DEPTH_TEST);
		//sceGuDepthMask(GL_TRUE);	// GL_TRUE to disable z-writes

		//GsEnableZbuffer1(GS_ENABLE, GS_ZBUFF_ALWAYS);
		//GsEnableZbuffer2(GS_ENABLE, GS_ZBUFF_ALWAYS);

		gsDepthMask(1);
		gsKit_set_test(gsGlobal, GS_ZTEST_OFF);
	}
	else
	{
		// Fixes Zfighting issues we have on the PSP.
		if (gRDPOtherMode.zmode == 3)
		{
			if (!ZFightingEnabled)
			{
				ZFightingEnabled = true;
				//sceGuDepthRange(65535, 80);
				gsDepthRange(65535.0f, 1.01f);
			}
		}
		else if (ZFightingEnabled)
		{
			ZFightingEnabled = false;
			//sceGuDepthRange(65535, 0);
			gsDepthRange(65535.0f, 1.0f);
		}

		// Enable or Disable ZBuffer test
		if ((mTnL.Flags.Zbuffer & gRDPOtherMode.z_cmp) | gRDPOtherMode.z_upd)
		{
			//sceGuEnable(GU_DEPTH_TEST);
			gsKit_set_test(gsGlobal, GS_ZTEST_ON);
		}
		else
		{
			//sceGuDisable(GU_DEPTH_TEST);
			gsKit_set_test(gsGlobal, GS_ZTEST_OFF);
		}

		// GL_TRUE to disable z-writes
		//sceGuDepthMask(gRDPOtherMode.z_upd ? GL_FALSE : GL_TRUE);
		gsDepthMask(gRDPOtherMode.z_upd ? 0 : 1);
	}

	// Initiate Texture Filter
	//
	// G_TF_AVERAGE : 1, G_TF_BILERP : 2 (linear)
	// G_TF_POINT   : 0 (nearest)
	//
	if ((gRDPOtherMode.text_filt != G_TF_POINT) | (gGlobalPreferences.ForceLinearFilter))
	{
		//sceGuTexFilter(GU_LINEAR, GU_LINEAR);
		if (CurrTex)
			CurrTex->Filter = GS_FILTER_LINEAR;
	}
	else
	{
		//sceGuTexFilter(GU_NEAREST, GU_NEAREST);
		if (CurrTex)
			CurrTex->Filter = GS_FILTER_NEAREST;
	}

	u32 cycle_mode = gRDPOtherMode.cycle_type;

	// Initiate Blender
	//
	if (cycle_mode < CYCLE_COPY && gRDPOtherMode.force_bl)
	{
		InitBlenderMode(gRDPOtherMode.blender);
	}
	else
	{
		//sceGuDisable(GU_BLEND);
		gsBlend = GS_SETTING_OFF;
	}

	// Initiate Alpha test
	//
	if ((gRDPOtherMode.alpha_compare == G_AC_THRESHOLD) && !gRDPOtherMode.alpha_cvg_sel)
	{
		u8 alpha_threshold = (mBlendColour.GetA());
		//sceGuAlphaFunc((alpha_threshold | g_ROM.ALPHA_HACK) ? GU_GEQUAL : GU_GREATER, alpha_threshold, 0xff);
		//sceGuEnable(GU_ALPHA_TEST);

		gsGlobal->Test->ATST = (alpha_threshold | g_ROM.ALPHA_HACK) ? ATST_GEQUAL : ATST_GREATER;
		gsGlobal->Test->AREF = alpha_threshold/2;
		gsGlobal->Test->AFAIL = 0;
		gsKit_set_test(gsGlobal, GS_ATEST_ON);

		//printf("alpha 1 %x\n", alpha_threshold);
	}
	else if (gRDPOtherMode.cvg_x_alpha)
	{
		// Going over 0x70 breaks OOT, but going lesser than that makes lines on games visible...ex: Paper Mario.
		// Also going over 0x30 breaks the birds in Tarzan :(. Need to find a better way to leverage this.
		//sceGuAlphaFunc(GU_GREATER, 0x70, 0xff);
		//sceGuEnable(GU_ALPHA_TEST);

		gsGlobal->Test->ATST = ATST_GREATER;
		gsGlobal->Test->AREF = 0x70/2;
		gsGlobal->Test->AFAIL = 0;
		gsKit_set_test(gsGlobal, GS_ATEST_ON);

		//printf("alpha 2\n");
	}
	else
	{
		//sceGuDisable(GU_ALPHA_TEST);

		gsKit_set_test(gsGlobal, GS_ATEST_OFF);
	}

	SBlendStateEntry		blend_entry;

	switch (cycle_mode)
	{
		case CYCLE_COPY:		blend_entry.States = mCopyBlendStates; break;
		case CYCLE_FILL:		blend_entry.States = mFillBlendStates; break;
		case CYCLE_1CYCLE:		blend_entry = LookupBlendState(mMux, false); break;
		case CYCLE_2CYCLE:		blend_entry = LookupBlendState(mMux, true); break;
	}

	//u32 render_flags{ GU_TEXTURE_32BITF | GU_COLOR_8888 | GU_VERTEX_32BITF | render_mode };

#ifdef DAEDALUS_DEBUG_DISPLAYLISTx
	// Used for Blend Explorer, or Nasty texture
	//
	if (DebugBlendmode(p_vertices, num_vertices, triangle_mode, render_flags, mMux))
		return;
#endif

	// This check is for inexact blends which were handled either by a custom blendmode or auto blendmode thing
	//
	if (blend_entry.OverrideFunction != nullptr)
	{
#ifdef DAEDALUS_DEBUG_DISPLAYLISTx
		// Used for dumping mux and highlight inexact blend
		//
		DebugMux(blend_entry.States, p_vertices, num_vertices, triangle_mode, render_flags, mMux);
#endif

		// Local vars for now
		SBlendModeDetails details;

		details.EnvColour = mEnvColour;
		details.PrimColour = mPrimitiveColour;
		details.InstallTexture = true;
		details.ColourAdjuster.Reset();

		blend_entry.OverrideFunction(details);

		bool installed_texture = false;

		if (details.InstallTexture)
		{
			u32 texture_idx = g_ROM.T1_HACK ? 1 : 0;

			if (mBoundTexture[texture_idx])
			{
				mBoundTexture[texture_idx]->InstallTexture();

				gsKit_tex_wrap(mTexWrap[texture_idx].u, mTexWrap[texture_idx].v);

				installed_texture = true;
			}
		}

		// If no texture was specified, or if we couldn't load it, clear it out
		if (!installed_texture)
		{
			//sceGuDisable(GU_TEXTURE_2D);
		}

		/*if (mTnL.Flags.Fog)
		{
			DaedalusVtx* p_FogVtx = static_cast<DaedalusVtx*>(malloc(num_vertices * sizeof(DaedalusVtx)));
			memcpy(p_FogVtx, p_vertices, num_vertices * sizeof(DaedalusVtx));
			details.ColourAdjuster.Process(p_vertices, num_vertices);
			//sceGuDrawArray(triangle_mode, render_flags, num_vertices, nullptr, p_vertices);
			DrawPrims(p_vertices, num_vertices, triangle_mode, installed_texture);
			RenderFog(p_FogVtx, num_vertices, triangle_mode, 0);

			free(p_FogVtx);
		}
		else*/
		{
			details.ColourAdjuster.Process(p_vertices, num_vertices);
			
			if (mTnL.Flags.Fog)
			{
				gsKit_fog_color(mFogColour.GetR(), mFogColour.GetG(), mFogColour.GetB());
			}
			
			//sceGuDrawArray(triangle_mode, render_flags, num_vertices, nullptr, p_vertices);
			DrawPrims(p_vertices, num_vertices, triangle_mode, installed_texture);
		}
	}
	else if (blend_entry.States != nullptr)
	{
		RenderUsingRenderSettings(blend_entry.States, p_vertices, num_vertices, triangle_mode, 0);
	}
	else
	{
#ifdef DAEDALUS_DEBUG_CONSOLE
		// Set default states
		DAEDALUS_ERROR("Unhandled blend mode");
#endif
		//sceGuDisable(GU_TEXTURE_2D);
		//sceGuDrawArray(triangle_mode, render_flags, num_vertices, nullptr, p_vertices);
		DrawPrims(p_vertices, num_vertices, triangle_mode, false);
	}
}

void RendererPS2::RenderUsingRenderSettings( const CBlendStates * states, DaedalusVtx * p_vertices, u32 num_vertices, u32 triangle_mode, u32 render_flags)
{
	//DAEDALUS_PROFILE( "RendererPS2::RenderUsingRenderSettings" );

	const CAlphaRenderSettings* alpha_settings(states->GetAlphaSettings());

	SRenderState	state;

	state.Vertices = p_vertices;
	state.NumVertices = num_vertices;
	state.PrimitiveColour = mPrimitiveColour;
	state.EnvironmentColour = mEnvColour;

	//Avoid copying vertices twice if we already save a copy to render fog //Corn
	/*DaedalusVtx* p_FogVtx(mVtx_Save);
	if (mTnL.Flags.Fog)
	{
		p_FogVtx = static_cast<DaedalusVtx*>(malloc(num_vertices * sizeof(DaedalusVtx)));
		memcpy(p_FogVtx, p_vertices, num_vertices * sizeof(DaedalusVtx));
	}
	else if (states->GetNumStates() > 1)
	{
		memcpy(mVtx_Save, p_vertices, num_vertices * sizeof(DaedalusVtx));
	}*/

	for (u32 i = 0; i < states->GetNumStates(); ++i)
	{
		const CRenderSettings* settings(states->GetColourSettings(i));

		bool install_texture0(settings->UsesTexture0() || alpha_settings->UsesTexture0());
		bool install_texture1(settings->UsesTexture1() || alpha_settings->UsesTexture1());

		SRenderStateOut out;

		memset(&out, 0, sizeof(out));

		settings->Apply(install_texture0 || install_texture1, state, out);
		alpha_settings->Apply(install_texture0 || install_texture1, state, out);

		// TODO: this nobbles the existing diffuse colour on each pass. Need to use a second buffer...
		/*if (i > 0)
		{
			memcpy(p_vertices, p_FogVtx, num_vertices * sizeof(DaedalusVtx));
		}*/

		if (out.VertexExpressionRGB != nullptr)
		{
			out.VertexExpressionRGB->ApplyExpressionRGB(state);
		}
		if (out.VertexExpressionA != nullptr)
		{
			out.VertexExpressionA->ApplyExpressionAlpha(state);
		}

		bool installed_texture = false;

		u32 texture_idx = 0;

		if (install_texture0 || install_texture1)
		{
			u32	tfx = GS_TFX_MODULATE;
			switch (out.BlendMode)
			{
				case PBM_MODULATE:		tfx = GS_TFX_MODULATE; break;
				case PBM_REPLACE:		tfx = GS_TFX_REPLACE; break;
				case PBM_BLEND:			tfx = GS_TFX_BLEND; gsTexEnvColor(out.TextureFactor.GetColour()); break;
			}

			gsTexFunc(tfx, out.BlendAlphaMode == PBAM_RGB ? GS_TCC_RGB : GS_TCC_RGBA);

			if (g_ROM.T1_HACK)
			{
				// NB if install_texture0 and install_texture1 are both set, 1 wins out
				texture_idx = install_texture1;

				const CNativeTexture* texture1 = mBoundTexture[1];

				if (install_texture1 && texture1 && mTnL.Flags.Texture && (mTnL.Flags._u32 & (TNL_LIGHT | TNL_TEXGEN)) != (TNL_LIGHT | TNL_TEXGEN))
				{
					float scale_x = texture1->GetScaleX();
					float scale_y = texture1->GetScaleY();

					gsTexOffset(-mTileTopLeft[1].s * scale_x / 4.f, -mTileTopLeft[1].t * scale_y / 4.f);
					gsTexScale(scale_x, scale_y);
				}
			}
			else
			{
				// NB if install_texture0 and install_texture1 are both set, 0 wins out
				texture_idx = install_texture0 ? 0 : 1;
			}

			CRefPtr<CNativeTexture> texture;

			if (out.MakeTextureWhite)
			{
				TextureInfo white_ti = mBoundTextureInfo[texture_idx];
				white_ti.SetWhite(true);
				texture = CTextureCache::Get()->GetOrCreateTexture(white_ti);
			}
			else
			{
				texture = mBoundTexture[texture_idx];
			}

			if (texture != nullptr)
			{
				texture->InstallTexture();
				installed_texture = true;
			}
		}

		// If no texture was specified, or if we couldn't load it, clear it out
		//if (!installed_texture) sceGuDisable(GU_TEXTURE_2D);

		gsKit_tex_wrap(mTexWrap[texture_idx].u, mTexWrap[texture_idx].v);

		if (mTnL.Flags.Fog)
		{
			gsKit_fog_color(mFogColour.GetR(), mFogColour.GetG(), mFogColour.GetB());
		}

		//sceGuDrawArray(triangle_mode, render_flags, num_vertices, nullptr, p_vertices);
		DrawPrims(p_vertices, num_vertices, triangle_mode, installed_texture);

		/*if (mTnL.Flags.Fog)
		{
			RenderFog(p_FogVtx, num_vertices, triangle_mode, render_flags);
		}*/
		
		/*if(p_FogVt)
			free(p_FogVt);*/
	}
}

void RendererPS2::TexRect( u32 tile_idx, const v2 & xy0, const v2 & xy1, TexCoord st0, TexCoord st1 )
{
	mTnL.Flags.Fog = 0;	//For now we force fog off for textrect, normally it should be fogged when depth_source is set //Corn

	UpdateTileSnapshots(tile_idx);

	// NB: we have to do this after UpdateTileSnapshot, as it set up mTileTopLeft etc.
	PrepareTexRectUVs(&st0, &st1);

	//printf("st: %d %d %d %d\n", st0.s, st0.t, st1.s, st1.t);

	// Convert fixed point uvs back to floating point format.
	// NB: would be nice to pass these as s16 ints, and use GU_TEXTURE_16BIT
	v2 uv0((float)st0.s / 32.f, (float)st0.t / 32.f);
	v2 uv1((float)st1.s / 32.f, (float)st1.t / 32.f);

	v2 screen0;
	v2 screen1;
	if (gGlobalPreferences.ViewportType == VT_FULLSCREEN_HD)
	{
		screen0.x = roundf(roundf(HD_SCALE * xy0.x) * mN64ToScreenScale.x + 59);	//59 in translate is an ugly hack that only work on 480x272 display//Corn
		screen0.y = roundf(roundf(xy0.y) * mN64ToScreenScale.y + mN64ToScreenTranslate.y);

		screen1.x = roundf(roundf(HD_SCALE * xy1.x) * mN64ToScreenScale.x + 59); //59 in translate is an ugly hack that only work on 480x272 display//Corn
		screen1.y = roundf(roundf(xy1.y) * mN64ToScreenScale.y + mN64ToScreenTranslate.y);
	}
	else
	{
		ConvertN64ToScreen(xy0, screen0);
		ConvertN64ToScreen(xy1, screen1);
	}

#ifdef DAEDALUS_DEBUG_DISPLAYLIST
	DL_PF("    Screen:  %.1f,%.1f -> %.1f,%.1f", screen0.x, screen0.y, screen1.x, screen1.y);
	DL_PF("    Texture: %.1f,%.1f -> %.1f,%.1f", uv0.x, uv0.y, uv1.x, uv1.y);
#endif
	const f32 depth = gRDPOtherMode.depth_source ? mPrimDepth : 0.0f;

#if 1	//1->SPRITE, 0->STRIP
	DaedalusVtx * p_vertices = static_cast<DaedalusVtx*>(malloc(2 * sizeof(DaedalusVtx)));

	p_vertices[0].Position.x = screen0.x;
	p_vertices[0].Position.y = screen0.y;
	p_vertices[0].Position.z = depth;
	p_vertices[0].Colour = c32(0xffffffff);
	p_vertices[0].Texture.x = uv0.x;
	p_vertices[0].Texture.y = uv0.y;

	p_vertices[1].Position.x = screen1.x;
	p_vertices[1].Position.y = screen1.y;
	p_vertices[1].Position.z = depth;
	p_vertices[1].Colour = c32(0xffffffff);
	p_vertices[1].Texture.x = uv1.x;
	p_vertices[1].Texture.y = uv1.y;

	RenderUsingCurrentBlendMode(p_vertices, 2, GS_PRIM_PRIM_SPRITE, 0 /*GU_TRANSFORM_2D*/, gRDPOtherMode.depth_source ? false : true);

#else
	//	To be used with TRIANGLE_STRIP, which requires 40% less verts than TRIANGLE
	//	For reference for future ports and if SPRITES( which uses %60 less verts than TRIANGLE) causes issues
	DaedalusVtx* p_vertices = static_cast<DaedalusVtx*>(malloc(4 * sizeof(DaedalusVtx)));

	p_vertices[0].Position.x = screen0.x;
	p_vertices[0].Position.y = screen0.y;
	p_vertices[0].Position.z = depth;
	p_vertices[0].Colour = c32(0xffffffff);
	p_vertices[0].Texture.x = uv0.x;
	p_vertices[0].Texture.y = uv0.y;

	p_vertices[1].Position.x = screen1.x;
	p_vertices[1].Position.y = screen0.y;
	p_vertices[1].Position.z = depth;
	p_vertices[1].Colour = c32(0xffffffff);
	p_vertices[1].Texture.x = uv1.x;
	p_vertices[1].Texture.y = uv0.y;

	p_vertices[2].Position.x = screen0.x;
	p_vertices[2].Position.y = screen1.y;
	p_vertices[2].Position.z = depth;
	p_vertices[2].Colour = c32(0xffffffff);
	p_vertices[2].Texture.x = uv0.x;
	p_vertices[2].Texture.y = uv1.y;

	p_vertices[3].Position.x = screen1.x;
	p_vertices[3].Position.y = screen1.y;
	p_vertices[3].Position.z = depth;
	p_vertices[3].Colour = c32(0xffffffff);
	p_vertices[3].Texture.x = uv1.x;
	p_vertices[3].Texture.y = uv1.y;

	RenderUsingCurrentBlendMode(p_vertices, 4, GS_PRIM_PRIM_TRISTRIP, 0 /*GU_TRANSFORM_2D*/, gRDPOtherMode.depth_source ? false : true);
#endif

	free(p_vertices);

#ifdef DAEDALUS_DEBUG_DISPLAYLIST
	++mNumRect;
#endif
}

void RendererPS2::TexRectFlip( u32 tile_idx, const v2 & xy0, const v2 & xy1, TexCoord st0, TexCoord st1 )
{
	mTnL.Flags.Fog = 0;	//For now we force fog off for textrect, normally it should be fogged when depth_source is set //Corn

	UpdateTileSnapshots(tile_idx);

	// NB: we have to do this after UpdateTileSnapshot, as it set up mTileTopLeft etc.
	PrepareTexRectUVs(&st0, &st1);

	// Convert fixed point uvs back to floating point format.
	// NB: would be nice to pass these as s16 ints, and use GU_TEXTURE_16BIT
	v2 uv0((float)st0.s / 32.f, (float)st0.t / 32.f);
	v2 uv1((float)st1.s / 32.f, (float)st1.t / 32.f);

	v2 screen0;
	v2 screen1;
	// FIXME(strmnnrmn): why is VT_FULLSCREEN_HD code in TexRect() not also done here?
	ConvertN64ToScreen(xy0, screen0);
	ConvertN64ToScreen(xy1, screen1);

#ifdef DAEDALUS_DEBUG_DISPLAYLIST
	DL_PF("    Screen:  %.1f,%.1f -> %.1f,%.1f", screen0.x, screen0.y, screen1.x, screen1.y);
	DL_PF("    Texture: %.1f,%.1f -> %.1f,%.1f", uv0.x, uv0.y, uv1.x, uv1.y);
#endif
	DaedalusVtx* p_vertices = static_cast<DaedalusVtx*>(malloc(4 * sizeof(DaedalusVtx)));

	p_vertices[0].Position.x = screen0.x;
	p_vertices[0].Position.y = screen0.y;
	p_vertices[0].Position.z = 0.0f;
	p_vertices[0].Colour = c32(0xffffffff);
	p_vertices[0].Texture.x = uv0.x;
	p_vertices[0].Texture.y = uv0.y;

	p_vertices[1].Position.x = screen1.x;
	p_vertices[1].Position.y = screen0.y;
	p_vertices[1].Position.z = 0.0f;
	p_vertices[1].Colour = c32(0xffffffff);
	p_vertices[1].Texture.x = uv0.x;
	p_vertices[1].Texture.y = uv1.y;

	p_vertices[2].Position.x = screen0.x;
	p_vertices[2].Position.y = screen1.y;
	p_vertices[2].Position.z = 0.0f;
	p_vertices[2].Colour = c32(0xffffffff);
	p_vertices[2].Texture.x = uv1.x;
	p_vertices[2].Texture.y = uv0.y;

	p_vertices[3].Position.x = screen1.x;
	p_vertices[3].Position.y = screen1.y;
	p_vertices[3].Position.z = 0.0f;
	p_vertices[3].Colour = c32(0xffffffff);
	p_vertices[3].Texture.x = uv1.x;
	p_vertices[3].Texture.y = uv1.y;

	// FIXME(strmnnrmn): shouldn't this pass gRDPOtherMode.depth_source ? false : true for the disable_zbuffer arg, as TextRect()?
	RenderUsingCurrentBlendMode(p_vertices, 4, GS_PRIM_PRIM_TRISTRIP, 0 /*GU_TRANSFORM_2D*/, true);

	free(p_vertices);

#ifdef DAEDALUS_DEBUG_DISPLAYLIST
	++mNumRect;
#endif
}

void RendererPS2::FillRect( const v2 & xy0, const v2 & xy1, u32 color )
{
	/*
		if ( (gRDPOtherMode._u64 & 0xffff0000) == 0x5f500000 )	//Used by Wave Racer
		{
			// this blend mode is mem*0 + mem*1, so we don't need to render it... Very odd!
			DAEDALUS_ERROR("	mem*0 + mem*1 - skipped");
			return;
		}
	*/
	// This if for C&C - It might break other stuff (I'm not sure if we should allow alpha or not..)
	//color |= 0xff000000;

	v2 screen0;
	v2 screen1;
	ConvertN64ToScreen(xy0, screen0);
	ConvertN64ToScreen(xy1, screen1);

#ifdef DAEDALUS_DEBUG_DISPLAYLIST
	DL_PF("    Screen:  %.1f,%.1f -> %.1f,%.1f", screen0.x, screen0.y, screen1.x, screen1.y);
#endif
	DaedalusVtx* p_vertices = static_cast<DaedalusVtx*>(malloc(2 * sizeof(DaedalusVtx)));

	// No need for Texture.x/y as we don't do any texturing for fillrect
	p_vertices[0].Position.x = screen0.x;
	p_vertices[0].Position.y = screen0.y;
	p_vertices[0].Position.z = 0.0f;
	p_vertices[0].Colour = c32(color);
	//p_vertices[0].Texture.x = 0.0f;
	//p_vertices[0].Texture.y = 0.0f;

	p_vertices[1].Position.x = screen1.x;
	p_vertices[1].Position.y = screen1.y;
	p_vertices[1].Position.z = 0.0f;
	p_vertices[1].Colour = c32(color);
	//p_vertices[1].Texture.x = 1.0f;
	//p_vertices[1].Texture.y = 0.0f;

	// FIXME(strmnnrmn): shouldn't this pass gRDPOtherMode.depth_source ? false : true for the disable_zbuffer arg, as TexRect()?
	RenderUsingCurrentBlendMode(p_vertices, 2, GS_PRIM_PRIM_SPRITE, 0 /*GU_TRANSFORM_2D*/, true);

	free(p_vertices);

#ifdef DAEDALUS_DEBUG_DISPLAYLIST
	++mNumRect;
#endif
}

void RendererPS2::Draw2DTexture(f32 x0, f32 y0, f32 x1, f32 y1,
								f32 u0, f32 v0, f32 u1, f32 v1,
								const CNativeTexture * texture)
{
	//DAEDALUS_PROFILE("RendererPSP::Draw2DTexture");

	//printf("RendererPS2:: %s \n", __func__);
	DaedalusVtx* p_verts = (DaedalusVtx*)malloc(4 * sizeof(DaedalusVtx));

	// Enable or Disable ZBuffer test
	if ((mTnL.Flags.Zbuffer & gRDPOtherMode.z_cmp) | gRDPOtherMode.z_upd)
	{
		//sceGuEnable(GU_DEPTH_TEST);
		gsKit_set_test(gsGlobal, GS_ZTEST_ON);
	}
	else
	{
		//sceGuDisable(GU_DEPTH_TEST);
		gsKit_set_test(gsGlobal, GS_ZTEST_OFF);
	}

	// GL_TRUE to disable z-writes
	//sceGuDepthMask(gRDPOtherMode.z_upd ? GL_FALSE : GL_TRUE);
	gsDepthMask(gRDPOtherMode.z_upd ? 0 : 1);
	//sceGuShadeModel(GU_FLAT);

	//ToDO: Set alpha/blend states according RenderUsingCurrentBlendMode?
	/*sceGuTexFilter(GU_LINEAR, GU_LINEAR);
	sceGuDisable(GU_ALPHA_TEST);
	sceGuTexFunc(GU_TFX_REPLACE, GU_TCC_RGBA);

	sceGuEnable(GU_BLEND);
	sceGuTexWrap(GU_CLAMP, GU_CLAMP);*/

	if (CurrTex)
		CurrTex->Filter = GS_FILTER_LINEAR;
	gsKit_set_test(gsGlobal, GS_ATEST_OFF);
	gsTexFunc(GS_TFX_REPLACE, GS_TCC_RGBA);
	gsBlend = GS_SETTING_ON;
	gsKit_tex_wrap(GU_CLAMP, GU_CLAMP);

	// Handle large images (width > 512) with blitting, since the PSP HW can't handle
	// Handling height > 512 doesn't work well? Ignore for now.
	/*if (u1 >= 1024)
	{

		Draw2DTextureBlit(x0, y0, x1, y1, u0, v0, u1, v1, texture);
		return;
	}*/

	p_verts[0].Position.x = N64ToScreenX(x0);
	p_verts[0].Position.y = N64ToScreenY(y0);
	p_verts[0].Position.z = 0.0f;
	p_verts[0].Colour = c32(0xffffffff);
	p_verts[0].Texture.x = u0;
	p_verts[0].Texture.y = v0;

	p_verts[1].Position.x = N64ToScreenX(x1);
	p_verts[1].Position.y = N64ToScreenY(y0);
	p_verts[1].Position.z = 0.0f;
	p_verts[1].Colour = c32(0xffffffff);
	p_verts[1].Texture.x = u1;
	p_verts[1].Texture.y = v0;

	p_verts[2].Position.x = N64ToScreenX(x0);
	p_verts[2].Position.y = N64ToScreenY(y1);
	p_verts[2].Position.z = 0.0f;
	p_verts[2].Colour = c32(0xffffffff);
	p_verts[2].Texture.x = u0;
	p_verts[2].Texture.y = v1;

	p_verts[3].Position.x = N64ToScreenX(x1);
	p_verts[3].Position.y = N64ToScreenY(y1);
	p_verts[3].Position.z = 0.0f;
	p_verts[3].Colour = c32(0xffffffff);
	p_verts[3].Texture.x = u1;
	p_verts[3].Texture.y = v1;

	//sceGuDrawArray(GU_TRIANGLE_STRIP, GU_TEXTURE_32BITF | GU_VERTEX_32BITF | GU_TRANSFORM_2D, 4, 0, p_verts);

	DrawPrims(p_verts, 4, GS_PRIM_PRIM_TRISTRIP, true);

	free(p_verts);
}

void RendererPS2::Draw2DTextureR(f32 x0, f32 y0, f32 x1, f32 y1,
								 f32 x2, f32 y2, f32 x3, f32 y3,
								 f32 s, f32 t)	// With Rotation
{
	//DAEDALUS_PROFILE("RendererPSP::Draw2DTextureR");

	//printf("RendererPS2::Draw2DTextureR");

	DaedalusVtx* p_verts = (DaedalusVtx*)malloc(4 * sizeof(DaedalusVtx));

	// Enable or Disable ZBuffer test
	if ((mTnL.Flags.Zbuffer & gRDPOtherMode.z_cmp) | gRDPOtherMode.z_upd)
	{
		//sceGuEnable(GU_DEPTH_TEST);
		gsKit_set_test(gsGlobal, GS_ZTEST_ON);
	}
	else
	{
		//sceGuDisable(GU_DEPTH_TEST);
		gsKit_set_test(gsGlobal, GS_ZTEST_OFF);
	}

	// GL_TRUE to disable z-writes
	/*sceGuDepthMask(gRDPOtherMode.z_upd ? GL_FALSE : GL_TRUE);*/
	gsDepthMask(gRDPOtherMode.z_upd ? 0 : 1);
	//sceGuShadeModel(GU_FLAT);

	//ToDO: Set alpha/blend states according RenderUsingCurrentBlendMode?
	/*sceGuTexFilter(GU_LINEAR, GU_LINEAR)
	sceGuDisable(GU_ALPHA_TEST);
	sceGuTexFunc(GU_TFX_REPLACE, GU_TCC_RGBA);

	sceGuEnable(GU_BLEND);*/

	if (CurrTex)
		CurrTex->Filter = GS_FILTER_LINEAR;
	gsKit_set_test(gsGlobal, GS_ATEST_OFF);
	gsTexFunc(GS_TFX_REPLACE, GS_TCC_RGBA);
	gsKit_tex_wrap(GU_CLAMP, GU_CLAMP);

	gsBlend = GS_SETTING_ON;

	p_verts[0].Position.x = N64ToScreenX(x0);
	p_verts[0].Position.y = N64ToScreenY(y0);
	p_verts[0].Position.z = 0.0f;
	p_verts[0].Colour = c32(0xffffffff);
	p_verts[0].Texture.x = 0.0f;
	p_verts[0].Texture.y = 0.0f;

	p_verts[1].Position.x = N64ToScreenX(x1);
	p_verts[1].Position.y = N64ToScreenY(y1);
	p_verts[1].Position.z = 0.0f;
	p_verts[1].Colour = c32(0xffffffff);
	p_verts[1].Texture.x = s;
	p_verts[1].Texture.y = 0.0f;

	p_verts[2].Position.x = N64ToScreenX(x2);
	p_verts[2].Position.y = N64ToScreenY(y2);
	p_verts[2].Position.z = 0.0f;
	p_verts[2].Colour = c32(0xffffffff);
	p_verts[2].Texture.x = s;
	p_verts[2].Texture.y = t;

	p_verts[3].Position.x = N64ToScreenX(x3);
	p_verts[3].Position.y = N64ToScreenY(y3);
	p_verts[3].Colour = c32(0xffffffff);
	p_verts[3].Position.z = 0.0f;
	p_verts[3].Texture.x = 0.0f;
	p_verts[3].Texture.y = t;

	//sceGuDrawArray(GU_TRIANGLE_FAN, GU_TEXTURE_32BITF | GU_VERTEX_32BITF | GU_TRANSFORM_2D, 4, 0, p_verts);
	DrawPrims(p_verts, 4, GS_PRIM_PRIM_TRISTRIP, true);

	free(p_verts);
}

// The following blitting code was taken from The TriEngine.
// See http://www.assembla.com/code/openTRI for more information.
void RendererPS2::Draw2DTextureBlit(f32 x, f32 y, f32 width, f32 height,
									f32 u0, f32 v0, f32 u1, f32 v1,
									const CNativeTexture * texture)
{
	if (!texture)
	{
#ifdef DAEDALUS_DEBUG_CONSOLE
		DAEDALUS_ERROR("No texture in Draw2DTextureBlit");
#endif
		return;
	}

	f32 cur_v = v0;
	f32 cur_y = y;
	f32 v_end = v1;
	f32 y_end = height;
	f32 vslice = 512.f;
	f32 ystep = (height / (v1 - v0) * vslice);
	f32 vstep = (v1 - v0) > 0 ? vslice : -vslice;

	f32 x_end = width;
	f32 uslice = 64.f;
	//f32 ustep = (u1-u0)/width * xslice;
	f32 xstep = (width / (u1 - u0) * uslice);
	f32 ustep = (u1 - u0) > 0 ? uslice : -uslice;

	const u8* data = static_cast<const u8*>(texture->GetData());

	for (; cur_y < y_end; cur_y += ystep, cur_v += vstep)
	{
		f32 cur_u = u0;
		f32 cur_x = x;
		f32 u_end = u1;

		f32 poly_height = ((cur_y + ystep) > y_end) ? (y_end - cur_y) : ystep;
		f32 source_height = vstep;

		// support negative vsteps
		if ((vstep > 0) && (cur_v + vstep > v_end))
		{
			source_height = (v_end - cur_v);
		}
		else if ((vstep < 0) && (cur_v + vstep < v_end))
		{
			source_height = (cur_v - v_end);
		}

		const u8* udata = data;
		// blit maximizing the use of the texture-cache
		for (; cur_x < x_end; cur_x += xstep, cur_u += ustep)
		{
			// support large images (width > 512)
			if (cur_u > 512.f || cur_u + ustep > 512.f)
			{
				s32 off = (ustep > 0) ? ((int)cur_u & ~31) : ((int)(cur_u + ustep) & ~31);

				udata += off * GetBitsPerPixel(texture->GetFormat());
				cur_u -= off;
				u_end -= off;
				//sceGuTexImage(0, Min<u32>(512, texture->GetCorrectedWidth()), Min<u32>(512, texture->GetCorrectedHeight()), texture->GetBlockWidth(), udata);
			}
			TextureVtx* p_verts = (TextureVtx*)malloc(2 * sizeof(TextureVtx));

			//f32 poly_width = ((cur_x+xstep) > x_end) ? (x_end-cur_x) : xstep;
			f32 poly_width = xstep;
			f32 source_width = ustep;

			// support negative usteps
			if ((ustep > 0) && (cur_u + ustep > u_end))
			{
				source_width = (u_end - cur_u);
			}
			else if ((ustep < 0) && (cur_u + ustep < u_end))
			{
				source_width = (cur_u - u_end);
			}

			p_verts[0].t0.x = cur_u;
			p_verts[0].t0.y = cur_v;
			p_verts[0].pos.x = N64ToScreenX(cur_x);
			p_verts[0].pos.y = N64ToScreenY(cur_y);
			p_verts[0].pos.z = 0;

			p_verts[1].t0.x = cur_u + source_width;
			p_verts[1].t0.y = cur_v + source_height;
			p_verts[1].pos.x = N64ToScreenX(cur_x + poly_width);
			p_verts[1].pos.y = N64ToScreenY(cur_y + poly_height);
			p_verts[1].pos.z = 0;

			//sceGuDrawArray(GU_SPRITES, GU_TEXTURE_32BITF | GU_VERTEX_32BITF | GU_TRANSFORM_2D, 2, 0, p_verts);

			free(p_verts);
		}
	}
}

#ifdef DAEDALUS_DEBUG_DISPLAYLIST
void RendererPS2::SelectPlaceholderTexture( EPlaceholderTextureType type )
{
	//printf("RendererPS2:: %s \n", __func__);
}
#endif // DAEDALUS_DEBUG_DISPLAYLIST

#ifdef DAEDALUS_DEBUG_DISPLAYLIST
// Used for Blend Explorer, or Nasty texture
bool RendererPS2::DebugBlendmode( DaedalusVtx * p_vertices, u32 num_vertices, u32 triangle_mode, u32 render_flags, u64 mux )
{
	//printf("RendererPS2:: %s \n", __func__);
	return false;
}
#endif // DAEDALUS_DEBUG_DISPLAYLIST


#ifdef DAEDALUS_DEBUG_DISPLAYLIST
void RendererPS2::DebugMux( const CBlendStates * states, DaedalusVtx * p_vertices, u32 num_vertices, u32 triangle_mode, u32 render_flags, u64 mux)
{
	//printf("RendererPS2:: %s \n", __func__);
}

#endif // DAEDALUS_DEBUG_DISPLAYLIST

bool CreateRenderer()
{
	#ifdef DAEDALUS_ENABLE_ASSERTS
	DAEDALUS_ASSERT_Q(gRenderer == nullptr);
	#endif
	gRendererPS2 = new RendererPS2();
	gRenderer    = gRendererPS2;
	return true;
}
void DestroyRenderer()
{
	delete gRendererPS2;
	gRendererPS2 = nullptr;
	gRenderer    = nullptr;
}

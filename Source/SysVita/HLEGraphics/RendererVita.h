#ifndef SYSVITA_HLEGRAPHICS_RENDERERVITA_H_
#define SYSVITA_HLEGRAPHICS_RENDERERVITA_H_

#include "HLEGraphics/BaseRenderer.h"

class RendererVita : public BaseRenderer
{
public:
    virtual void RestoreRenderStates();

    virtual void RenderTriangles(DaedalusVtx *p_vertices, u32 num_vertices, bool disable_zbuffer);

    virtual void TexRect(u32 tile_idx, const v2 & xy0, const v2 & xy1, TexCoord st0, TexCoord st1);
    virtual void TexRectFlip(u32 tile_idx, const v2 & xy0, const v2 & xy1, TexCoord st0, TexCoord st1);
    virtual void FillRect(const v2 & xy0, const v2 & xy1, TexCoord st0, TexCoord st1);

    virtual void Draw2DTexture(f32 x0, f32 y0, f32 x1, f32 y1,
                               f32 u0, f32 v0, f32 u1, f32 v1, const CNativeTexture *texture);
    virtual void Draw2DTextureR(f32 x0, f32 y0, f32 x1, f32 y1,
                                f32 x2, f32 y2, f32 x3, f32 y3,
                                f32 s,  f32 t);

  private:
      void MakeShaderConfigFromCurrentState( struct ShaderConfiguration *config) const;

      void PrepareRenderState(const float (&mat_project)[16], bool disable_zbuffer);

      void RenderDaedalusVtx(int prim, const DaedalusVtx *vertices, int count);
      void RenderDaedalusVtxStream(int prim, const float *positions, const TexCoord *uvx, const u32 *colours, int count);
};
      extern RendererVita *RendererVita;

      #endif

/*
Copyright (C) 2019 DaedalusX64 Team (Wally)

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
*/


#include "stdafx.h"

#include <stdio.h>

#include "Core/Memory.h"

#include "Debug/DBGConsole.h"

#include "Graphics/GraphicsContext.h"

#include "HLEGraphics/BaseRenderer.h"
#include "HLEGraphics/TextureCache.h"
#include "HLEGraphics/DLParser.h"
#include "HLEGraphics/DisplayListDebugger.h"

#include "Plugins/GraphicsPlugin.h"

#include "Utility/Timing.h"

u32                 gVISyncRate     = 1500;

// This is an extremely basic graphics plugin for now, doesn't do anything yet

class CGraphicsPluginVita : public CGraphicsPlugin
{
public:
    CGraphicsPluginVita();
    ~CGraphicsPluginVita();

    bool Initialise();

    virtual bool StartEmulation() { return true; }

    virtual void		ViStatusChanged()		{}
  	virtual void		ViWidthChanged()		{}

    virtual void ProcessDList();

    virtual void UpdateScreen();

    virtual void RomClosed();

private:
    u32 LastOrigin;

};

CGraphicsPluginVita::CGraphicsPluginVita()
:   LastOrigin( 0 )
{}

CGraphicsPluginVita::~CGraphicsPluginVita() {}


bool CGraphicsPluginVita::Initialise()
{
// Skeleton
  return true;

}


void CGraphicsPluginVita::ProcessDList()
{
  DLParser_Process();
}

void CGraphicsPluginVita::UpdateScreen() {}

void CGraphicsPluginVita::RomClosed() {}


class CGraphicsPlugin * CreateGraphicsPlugin()
{
    #ifdef DAEDALUS_DEBUG_CONSOLE
    DBGConsole_Msg( 0, "Initialising Graphics Plugin [CVITA]" );
#endif

    CGraphicsPluginVita * plugin = new CGraphicsPluginVita;
    if( !plugin->Initialise() )
    {
        delete plugin;
        plugin = nullptr;
    }

    return plugin;
}

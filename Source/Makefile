
BIN2C = $(PS2SDK)/bin/bin2c

BASE_FILES = StdAfx.o
CONFIG_FILES = Config/ConfigOptions.o
CORE_FILES = Core/Cheats.o Core/CPU.o Core/DMA.o Core/Dynamo.o Core/FlashMem.o Core/Interpret.o Core/Interrupts.o Core/JpegTask.o Core/Memory.o Core/PIF.o Core/R4300.o Core/ROM.o Core/ROMBuffer.o Core/ROMImage.o Core/RomSettings.o Core/RSP_HLE.o Core/Save.o Core/SaveState.o Core/TLB.o
DEBUG_FILES = Debug/DebugConsoleImpl.o Debug/DebugLog.o Debug/Dump.o
DYNAREC_FILES = DynaRec/BranchType.o DynaRec/DynaRecProfile.o DynaRec/Fragment.o DynaRec/FragmentCache.o DynaRec/IndirectExitMap.o DynaRec/StaticAnalysis.o DynaRec/TraceRecorder.o
GRAPHICS_FILES = Graphics/ColourValue.o Graphics/PngUtil.o Graphics/TextureTransform.o
HLEAUDIO_FILES = HLEAudio/AudioHLEProcessor.o HLEAudio/ABI1.o HLEAudio/ABI2.o HLEAudio/ABI3.o HLEAudio/ABI3mp3.o HLEAudio/AudioBuffer.o HLEAudio/HLEMain.o HLEAudio/ABI_ADPCM.o HLEAudio/ABI_Buffers.o HLEAudio/ABI_Filters.o HLEAudio/ABI_MixerInterleave.o HLEAudio/ENV_Mixer.o HLEAudio/ABI_Resample.o
HLEGRAPHICS_FILES = HLEGraphics/BaseRenderer.o HLEGraphics/CachedTexture.o HLEGraphics/ConvertImage.o HLEGraphics/ConvertTile.o HLEGraphics/DLDebug.o HLEGraphics/DLParser.o HLEGraphics/Microcode.o HLEGraphics/RDP.o HLEGraphics/RDPStateManager.o HLEGraphics/TextureCache.o HLEGraphics/TextureInfo.o HLEGraphics/uCodes/Ucode.o
INTERFACE_FILES = Interface/RomDB.o
MATH_FILES = Math/Matrix4x4.o
OSHLE_FILES = OSHLE/OS.o OSHLE/patch.o
PLUGIN_FILES = Plugins/GraphicsPlugin.o
SYSTEM_FILES = System/Paths.o System/System.o
TEST_FILES = Test/BatchTest.o
UTILITY_FILES = Utility/CRC.o Utility/DataSink.o Utility/FastMemcpy.o  Utility/FramerateLimiter.o Utility/Hash.o Utility/IniFile.o Utility/MemoryHeap.o Utility/Preferences.o Utility/PrintOpCode.o Utility/Profiler.o Utility/ROMFile.o Utility/ROMFileCache.o Utility/ROMFileCompressed.o Utility/ROMFileMemory.o Utility/ROMFileUncompressed.o Utility/Stream.o Utility/StringUtil.o Utility/Synchroniser.o Utility/Timer.o Utility/Translate.o Utility/ZLibWrapper.o
UNKNOWN_FILES = Utility/FastMemcpy_test.o Utility/MemoryPool.o
DEBUG_ONLY = Core/Registers.o

BUILD = $(BASE_FILES) $(CONFIG_FILES) $(CORE_FILES) $(DEBUG_FILES) $(DYNAREC_FILES) $(GRAPHICS_FILES) $(HLEAUDIO_FILES) $(HLEGRAPHICS_FILES) $(INTERFACE_FILES) $(MATH_FILES) $(OSHLE_FILES) $(PLUGIN_FILES) $(SYSTEM_FILES) $(TEST_FILES) $(UTILITY_FILES) $(DEBUG_ONLY)

PS2_MAIN_FILES = SysPS2/main.o
PS2_INPUTMANAGER_FILES = SysPS2/Input/InputManagerPS2.o
PS2_UTILITY_FILES = SysPS2/Utility/IOPS2.o SysPS2/Utility/ThreadPS2.o SysPS2/Utility/TimingPS2.o
PS2_HLEAUDIO_FILES = SysPS2/HLEAudio/AudioPluginPS2.o
PS2_DYNAREC_FILES = SysPS2/DynaRec/AssemblyUtilsPS2.o SysPS2/DynaRec/AssemblyWriterPS2.o SysPS2/DynaRec/CodeBufferManagerPS2.o SysPS2/DynaRec/CodeGeneratorPS2.o SysPS2/DynaRec/DynaRecStubs.o SysPS2/DynaRec/DynarecTargetPS2.o SysPS2/DynaRec/N64RegisterCachePS2.o 
PS2_GRAPHICS_FILES = SysPS2/Graphics/GraphicsContext.o SysPS2/Graphics/NativeTexturePS2.o SysPS2/Graphics/DrawText.o 
PS2_HLEGRAPHICS_FILES = SysPS2/HLEGraphics/GraphicsPluginPS2.o SysPS2/HLEGraphics/RendererPS2.o SysPS2/HLEGraphics/DisplayListDebugger.o SysPS2/HLEGraphics/Blender.o SysPS2/HLEGraphics/BlendModes.o SysPS2/HLEGraphics/ColourAdjuster.o SysPS2/HLEGraphics/Combiner/BlendConstant.o SysPS2/HLEGraphics/Combiner/CombinerExpression.o SysPS2/HLEGraphics/Combiner/CombinerTree.o SysPS2/HLEGraphics/Combiner/RenderSettings.o SysPS2/HLEGraphics/VectorClipping.o SysPS2/HLEGraphics/TnLVU0.o
PS2_DEBUG_FILES = SysPS2/Debug/DaedalusAssertPS2.o SysPS2/Debug/DBGConsolePS2.o 
PS2_UI_FILES = SysPS2/UI/AboutComponent.o SysPS2/UI/AdjustDeadzoneScreen.o SysPS2/UI/AdvancedOptionsScreen.o SysPS2/UI/CheatOptionsScreen.o SysPS2/UI/ColourPulser.o SysPS2/UI/Dialogs.o SysPS2/UI/GlobalSettingsComponent.o SysPS2/UI/MainMenuScreen.o SysPS2/UI/PauseOptionsComponent.o SysPS2/UI/PauseScreen.o SysPS2/UI/RomPreferencesScreen.o SysPS2/UI/RomSelectorComponent.o SysPS2/UI/SavestateSelectorComponent.o SysPS2/UI/SelectedRomComponent.o SysPS2/UI/SplashScreen.o SysPS2/UI/UICommand.o SysPS2/UI/UIComponent.o SysPS2/UI/UIContext.o SysPS2/UI/UIElement.o SysPS2/UI/UIScreen.o SysPS2/UI/UISetting.o 

PS2_BUILD = $(PS2_MAIN_FILES) $(PS2_INPUTMANAGER_FILES) $(PS2_UTILITY_FILES) $(PS2_HLEAUDIO_FILES) $(PS2_DYNAREC_FILES) $(PS2_GRAPHICS_FILES) $(PS2_HLEGRAPHICS_FILES) $(PS2_DEBUG_FILES) $(PS2_UI_FILES)
IRXS = iomanX_irx.o fileXio_irx.o usbhdfsd_irx.o usbd_irx.o libsd_irx.o audsrv_irx.o poweroff_irx.o ps2dev9_irx.o ps2atad_irx.o ps2hdd_irx.o ps2fs_irx.o smscdvd_irx.o

CONFIG = Release
#CONFIG = Dev

EE_BIN 	= Daedalus.elf
EE_INCS += -I$(PS2SDK)/ports/include -I$(PS2DEV)/gskit/include -I./SysPS2/Include -I./Config/$(CONFIG)
EE_CXXFLAGS	= -O2 -G0 -Wall -g -std=c++14
EE_LDFLAGS += -L$(PS2SDK)/ports/lib -L$(PS2DEV)/gsKit/lib
EE_LIBS += -laudsrv -lcdvd -lpng -lz -lfileXio -lgskit -ldmakit -lvux -lpatches -lpad -lm -lhdd
EE_OBJS = $(BUILD) $(PS2_BUILD) $(IRXS) 

all: $(EE_BIN)

%_irx.c: SysPS2/Utility/SMSCDVD/%.irx
	$(BIN2C) $^ $*_irx.c $*_irx
SysPS2/Utility/SMSCDVD/smscdvd.irx:
	make -C SysPS2/Utility/SMSCDVD/
%_irx.c: $(PS2SDK)/iop/irx/%.irx
	$(BIN2C) $^ $*_irx.c $*_irx
pack:
	ps2-packer-lite $(EE_BIN) $(EE_BIN:.elf=-packed.elf)
run:
	ps2client -h 192.168.8.10 execee host:$(EE_BIN)
reset:
	ps2client -h 192.168.8.10 reset
listen:
	ps2client -h 192.168.8.10 listen
strip:
	ee-strip $(EE_BIN)
teste:
	ee-addr2line -e $(EE_BIN) 001b3f58
clean:
	rm -f $(EE_BIN) $(EE_OBJS) *_irx.s
	make -C SysPS2/Utility/SMSCDVD/ clean

include $(PS2SDK)/samples/Makefile.pref
include $(PS2SDK)/samples/Makefile.eeglobal_cpp

#!/bin/bash
export PLATFORM=$( echo $1 | cut -d "_" -f1 )
export BUILDTYPE=$( echo $1 | cut -d "_" -f2- )


function usage() {
    echo "Usage ./build_daedalus.sh BUILD_TYPE"
    echo "Build Types:"
    echo "PSP Release = PSP_RELEASE"
    echo "PSP Debug = PSP_DEBUG"
    echo "Linux Release = LINUX_RELEASE"
    echo "Mac Release = MAC_RELEASE"
    exit
}

function pre_prep(){

    if [ -d $PWD/daedbuild ]; then
        echo "Removing previous build attempt"
        rm -r "$PWD/daedbuild"
        mkdir "$PWD/daedbuild"
    fi

    if [ -d $PWD/DaedalusX64 ]; then
        rm -r $PWD/DaedalusX64/EBOOT.PBP
    else
        mkdir $PWD/DaedalusX64
        mkdir ../DaedalusX64/SaveStates
        mkdir ../DaedalusX64/SaveGames
        mkdir ../DaedalusX64/Roms
    fi

}

function finalPrep() {

    if [ ! -d ../DaedalusX64 ]; then
        mkdir ../DaedalusX64/SaveStates
        mkdir ../DaedalusX64/SaveGames
        mkdir ../DaedalusX64/Roms
    fi

    if [ -f "$PWD/EBOOT.PBP" ]; then
        mv "$PWD/EBOOT.PBP" ../DaedalusX64/
        cp -r ../Data/* ../DaedalusX64/
    else
        cp -r ../Data/* ../DaedalusX64/
        cp ../Source/SysGL/HLEGraphics/n64.psh ../DaedalusX64
    fi
}

function buildPSP() {

  make -C "$PWD/../Source/SysPSP/PRX/DveMgr"
  make -C "$PWD/../Source/SysPSP/PRX/ExceptionHandler"
  make -C "$PWD/../Source/SysPSP/PRX/KernelButtons"
  make -C "$PWD/../Source/SysPSP/PRX/MediaEngine"

  make -j8
  #No point continuing if the elf file doesn't exist
  if [ -f "$PWD/daedalus.elf" ]; then
    #Pack PBP
    psp-fixup-imports daedalus.elf
    mksfoex -d MEMSIZE=1 DaedalusX64 PARAM.SFO
    psp-prxgen daedalus.elf daedalus.prx
    cp ../Source/SysPSP/Resources/eboot_icons/* "$PWD"
    pack-pbp EBOOT.PBP PARAM.SFO icon0.png NULL NULL pic1.png NULL daedalus.prx NULL
    finalPrep
  fi
                    }
## Main loop

if [ $PLATFORM = "PSP" ]; then
  pre_prep
    mkdir "$PWD/daedbuild"
    cd "$PWD/daedbuild"
cmake -DCMAKE_TOOLCHAIN_FILE=../Tools/psptoolchain.cmake -DPSP=1 ../Source
buildPSP

elif [ $PLATFORM = "VITA" ]; then
	pre_prep
	mkdir "$PWD/daedbuild"
	cd "$PWD/daedbuild"
	cmake -DCMAKE_TOOLCHAIN_FILE=$VITASDK/share/vita.toolchain.cmake -DVITA=1 ../Source
	make -j8
	finalPrep

else
usage
fi

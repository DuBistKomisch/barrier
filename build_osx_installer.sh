#!/bin/sh

# change this to rename the installer package
B_DMG="Barrier-v1.9.dmg"

cd $(dirname $0)

# sanity check so we don't distribute packages full of debug symbols
B_BUILD_TYPE=$(grep -E ^CMAKE_BUILD_TYPE build/CMakeCache.txt | cut -d= -f2)
if [ "$B_BUILD_TYPE" != "Release" ]; then
    echo Will only build installers for Release builds
    exit 1
fi

B_REREF_SCRIPT=$(pwd)/osx_reref_dylibs.sh
if [ ! -x $B_REREF_SCRIPT ]; then
    echo Missing script: $B_REREF_SCRIPT
    exit 1
fi

# remove any old copies so there's no confusion about whever this
# process completes successfully or not
rm -rf build/bundle/{bundle.dmg,$B_DMG}

B_BINARY_PATH=$(pwd)/build/bin
cd build/bundle/Barrier.app/Contents 2>/dev/null
if [ $? -ne 0 ]; then
    echo Please make sure that the build completed successfully
    echo before trying to create the installer.
    exit 1
fi

# MacOS folder holds the executables, non-system libraries,
# and the startup script
rm -rf MacOS
mkdir MacOS || exit 1
cd MacOS || exit 1

# copy all executables
cp ${B_BINARY_PATH}/* . || exit 1

# copy the qt platform plugin
# TODO: this is hacky and will probably break if there is more than one qt
# version installed. need a better way to find this library
B_COCOA=$(find /usr/local/Cellar/qt -type f -name libqcocoa.dylib | head -1)
if [ $? -ne 0 ] || [ "x$B_COCOA" = "x" ]; then
    echo "Could not find cocoa platform plugin"
    exit 1
fi
mkdir platforms
cp $B_COCOA platforms/ || exit 1

# make sure we can r/w all these binaries
chmod -R u+rw * || exit 1

# only one executable (barrier) needs non-system libraries although it's
# libraries can call each other. use a recursive script to handle the
# re-referencing
$B_REREF_SCRIPT barrier || exit 1
# the cocoa platform plugin also needs to know where to find the qt libraries.
# because it exists in a subdirectory we append ../ to the relative path of the
# libraries in its metadata
$B_REREF_SCRIPT platforms/libqcocoa.dylib ../ || exit 1

# create a startup script that will change to the binary directory
# before starting barrier
printf "%s\n" "#!/bin/sh" "cd \$(dirname \$0)" "exec ./barrier" > barrier.sh
chmod +x barrier.sh

# create the DMG to be distributed in build/bundle
cd ../../..
hdiutil create -size 64m -fs HFS+ -volname "Barrier" bundle.dmg || exit 1
hdiutil attach bundle.dmg -mountpoint mnt || exit 1
cp -r Barrier.app mnt/ || exit 1
hdiutil detach mnt || exit 1
hdiutil convert bundle.dmg -format UDZO -o $B_DMG || exit 1
rm bundle.dmg

echo "Installer created successfully"
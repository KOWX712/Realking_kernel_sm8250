#!/bin/bash
#set -e

# Copy this script inside the kernel directory

# Define variables
DIR=$(readlink -f .)
ZIMAGE_DIR="$(pwd)/out/arch/arm64/boot"
KERNEL_DEFCONFIG=munch_defconfig

LINKER="lld"
MAKE="./makeparallel"
BUILD_START=$(date +"%s")
TIME="$(date "+%Y%m%d-%H%M%S")"

# Colors
blue='\033[0;34m'
nocol='\033[0m'


# Check if the clang compiler is present, if not, clone it from GitHub
if [ ! -d "$DIR/clang" ]; then
    echo "No clang compiler found ... Cloning from GitHub"

    # Prompt user to choose Clang version
    echo "Choose which Clang to use:"
    echo "1. ZyC Stable (Clang 16.0.6)"
    echo "2. WeebX Stable (Cland 19.1.5)"
    read -p "Enter the number of your choice: " clang_choice

    # Set URL and archive name based on user choice
    case "$clang_choice" in
        1)
            CLANG_URL=$(curl -s https://raw.githubusercontent.com/v3kt0r-87/Clang-Stable/main/clang-zyc.txt)
            ARCHIVE_NAME="zyc-clang.tar.gz"
            ;;
        2)
            CLANG_URL=$(curl -s https://raw.githubusercontent.com/v3kt0r-87/Clang-Stable/main/clang-weebx.txt)
            ARCHIVE_NAME="weebx-clang.tar.gz"
            ;;
        3)
            CLANG_URL=$(curl -s https://raw.githubusercontent.com/v3kt0r-87/Clang-Stable/main/clang-weebx-beta.txt)
            ARCHIVE_NAME="weebx-clang-beta.tar.gz"
            ;;
        *)
            echo "Invalid choice. Exiting..."
            exit 1
            ;;
    esac

    # Download Clang archive
    echo "Downloading Clang ... Please Wait ..."
    if ! wget -P "$DIR" "$CLANG_URL" -O "$DIR/$ARCHIVE_NAME"; then
        echo "Failed to download Clang. Exiting..."
        exit 1
    fi

    # Create clang directory and extract archive
    mkdir -p "$DIR/clang"
    if ! tar -xvf "$DIR/$ARCHIVE_NAME" -C "$DIR/clang"; then
        echo "Failed to extract Clang. Exiting..."
        exit 1
    fi

    # Clean up
    rm -f "$DIR/$ARCHIVE_NAME"

    # Verify directory creation
    if [ ! -d "$DIR/clang" ]; then
        echo "Failed to create the 'clang' directory. Exiting..."
        exit 1
    fi
fi

# Set up environment variables for the build
export PATH="$DIR/clang/bin:$PATH"
export ARCH=arm64
export SUBARCH=arm64
export KBUILD_COMPILER_STRING="$($DIR/clang/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')"

clear

# Add KernelSU driver
curl -LSs "https://raw.githubusercontent.com/backslashxx/KernelSU/master/kernel/setup.sh" | bash

# Let's make the version consist with KowSU
count=$(gh api "repos/KOWX712/KernelSU/commits?per_page=1" --include --silent 2>/dev/null | grep -i '^link:' | jq -Rr 'capture("page=(?<count>[0-9]+)>; rel=\"last\"").count')
version=$(( count + 30000 ))
[ -n $count ] && sed -i "s/-DKSU_VERSION=.*/-DKSU_VERSION=$version/" KernelSU/kernel/Makefile

# Display initialization message
echo -e "$blue***********************************************"
echo "          Initializing Kernel Compilation          "
echo -e "***********************************************$nocol"

# Prompt user to choose the build type (MIUI or AOSP)
echo "Choose the build type:"
echo "1. Hyper Os"
echo "2. AOSP"
# read -p "Enter the number of your choice: " build_choice
build_choice=1

# Modify dtsi file if MIUI build is selected
if [ "$build_choice" = "1" ]; then
    sed -i 's/qcom,mdss-pan-physical-width-dimension = <70>;$/qcom,mdss-pan-physical-width-dimension = <695>;/' arch/arm64/boot/dts/vendor/qcom/dsi-panel-l11r-38-08-0a-dsc-cmd.dtsi
    sed -i 's/qcom,mdss-pan-physical-height-dimension = <155>;$/qcom,mdss-pan-physical-height-dimension = <1546>;/' arch/arm64/boot/dts/vendor/qcom/dsi-panel-l11r-38-08-0a-dsc-cmd.dtsi
    zip_name="HyperOs"
elif [ "$build_choice" = "2" ]; then
    echo "AOSP build selected. No modifications needed."
    zip_name="AOSP"
else
    echo "Invalid choice. Exiting..."
    exit 1
fi

# Build the kernel
echo "**** Kernel defconfig is set to $KERNEL_DEFCONFIG ****"
echo -e "$blue***********************************************"
echo "          BUILDING KERNEL          "
echo -e "***********************************************$nocol"
make $KERNEL_DEFCONFIG O=out CC=clang
make -j$(nproc --all) O=out \
                      CC=clang \
                      ARCH=arm64 \
                      CROSS_COMPILE=aarch64-linux-gnu- \
                      NM=llvm-nm \
                      OBJDUMP=llvm-objdump \
                      STRIP=llvm-strip

# Create a zip file with the built kernel
mkdir -p tmp
cp -fp $ZIMAGE_DIR/Image.gz tmp
cp -fp $ZIMAGE_DIR/dtbo.img tmp
cp -fp $ZIMAGE_DIR/dtb tmp
cp -rp ./anykernel/* tmp
cd tmp
7za a -mx9 tmp.zip *
cd ..
rm -f *.zip
cp -fp tmp/tmp.zip RealKing-Munch-${zip_name}-$TIME.zip
rm -rf tmp
echo $TIME

# Function to revert changes made to the dtsi file
revert_changes() {
    sed -i 's/qcom,mdss-pan-physical-width-dimension = <695>;$/qcom,mdss-pan-physical-width-dimension = <70>;/' arch/arm64/boot/dts/vendor/qcom/dsi-panel-l11r-38-08-0a-dsc-cmd.dtsi
    sed -i 's/qcom,mdss-pan-physical-height-dimension = <1546>;$/qcom,mdss-pan-physical-height-dimension = <155>;/' arch/arm64/boot/dts/vendor/qcom/dsi-panel-l11r-38-08-0a-dsc-cmd.dtsi
}

# Revert changes after compiling kernel
# revert_changes
git checkout -- .

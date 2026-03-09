#!/bin/zsh
#
# Build script for Pique

# Variables
XCODE_PATH="$(xcode-select -p | sed 's|/Contents/Developer||')"
APP_SIGNING_IDENTITY="Developer ID Application: Mac Admins Open Source (T4SK8ZXCXG)"
INSTALLER_SIGNING_IDENTITY="Developer ID Installer: Mac Admins Open Source (T4SK8ZXCXG)"
MP_SHA="71c57fcfdf43692adcd41fa7305be08f66bae3e5"
MP_BINDIR="/tmp/munki-pkg"
CONSOLEUSER=$(/usr/bin/stat -f "%Su" /dev/console)
TOOLSDIR=$(dirname $0)
BUILDSDIR="$TOOLSDIR/build"
OUTPUTSDIR="$TOOLSDIR/outputs"
MP_ZIP="/tmp/munki-pkg.zip"
XCODE_BUILD_PATH="$XCODE_PATH/Contents/Developer/usr/bin/xcodebuild"
XCODE_NOTARY_PATH="$XCODE_PATH/Contents/Developer/usr/bin/notarytool"
XCODE_STAPLER_PATH="$XCODE_PATH/Contents/Developer/usr/bin/stapler"
MARKETING_VERSION=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' "$TOOLSDIR/Pique.xcodeproj/project.pbxproj" | head -1 | tr -d '[:space:]')
NEWSUBBUILD=$((100 + $(git rev-parse HEAD~0 | xargs -I{} git rev-list --count {})))

# Use marketing version as the release version, build number for internal tracking
AUTOMATED_PIQUE_BUILD="$MARKETING_VERSION"
/usr/bin/xcrun agvtool new-version -all $NEWSUBBUILD

# Create files to use for build process info
echo "$AUTOMATED_PIQUE_BUILD" > $TOOLSDIR/build_info.txt
echo "$MARKETING_VERSION" > $TOOLSDIR/build_info_main.txt

if [ -e $XCODE_BUILD_PATH ]; then
  XCODE_BUILD="$XCODE_BUILD_PATH"
else
  ls -la /Applications
  echo "Could not find required Xcode build. Exiting..."
  exit 1
fi

# Build Pique
echo "Building Pique"
$XCODE_BUILD -project "$TOOLSDIR/Pique.xcodeproj" -scheme "Pique" -configuration Release -derivedDataPath "$BUILDSDIR/DerivedData" CODE_SIGN_IDENTITY=$APP_SIGNING_IDENTITY OTHER_CODE_SIGN_FLAGS="--timestamp" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
XCB_RESULT="$?"
if [ "${XCB_RESULT}" != "0" ]; then
    echo "Error running xcodebuild: ${XCB_RESULT}" 1>&2
    exit 1
fi

# Zip application for notary
/bin/mkdir -p "$BUILDSDIR"
/usr/bin/ditto -c -k --keepParent "$BUILDSDIR/DerivedData/Build/Products/Release/Pique.app" "${BUILDSDIR}/Pique.zip"

DITTO_RESULT="$?"
if [ "${DITTO_RESULT}" != "0" ]; then
    echo "Error running ditto: ${DITTO_RESULT}" 1>&2
    exit 1
fi

# Setup notary item
$XCODE_NOTARY_PATH store-credentials --apple-id "opensource@macadmins.io" --team-id "T4SK8ZXCXG" --password "$2" pique
# Notarize Pique application
$XCODE_NOTARY_PATH submit "${BUILDSDIR}/Pique.zip" --keychain-profile "pique" --wait

# Create outputs folder
if [ -e $OUTPUTSDIR ]; then
  /bin/rm -rf $OUTPUTSDIR
fi
/bin/mkdir -p "$OUTPUTSDIR"

if ! [ -n "$1" ]; then
  echo "Did not pass option to create package"
  # Move notarized zip to outputs folder
  /bin/mv "${BUILDSDIR}/Pique.zip" "$OUTPUTSDIR"
  exit 0
fi

# Download specific version of munki-pkg
echo "Downloading munki-pkg tool from github..."
if [ -f "${MP_ZIP}" ]; then
    /usr/bin/sudo /bin/rm -rf ${MP_ZIP}
fi
/usr/bin/curl https://github.com/munki/munki-pkg/archive/${MP_SHA}.zip -L -o ${MP_ZIP}
if [ -d ${MP_BINDIR} ]; then
    /usr/bin/sudo /bin/rm -rf ${MP_BINDIR}
fi
/usr/bin/unzip ${MP_ZIP} -d ${MP_BINDIR}
DL_RESULT="$?"
if [ "${DL_RESULT}" != "0" ]; then
    echo "Error downloading munki-pkg tool: ${DL_RESULT}" 1>&2
    exit 1
fi

# Create the package
echo "Creating Pique package"
PKG_PATH="$TOOLSDIR/PiquePkg"
if [ -e $PKG_PATH ]; then
  /bin/rm -rf $PKG_PATH
fi
/bin/mkdir -p "$PKG_PATH/payload"
/bin/mkdir -p "$PKG_PATH/scripts"
/usr/bin/sudo /usr/sbin/chown -R ${CONSOLEUSER}:wheel "$PKG_PATH"
/bin/cp -R "$BUILDSDIR/DerivedData/Build/Products/Release/Pique.app" "$PKG_PATH/payload/Pique.app"

# Create postinstall script to register the QuickLook extension
/bin/cat << 'POSTINSTALL' > "$PKG_PATH/scripts/postinstall"
#!/bin/zsh
# Register the QuickLook preview extension
/usr/bin/pluginkit -a /Applications/Pique.app/Contents/PlugIns/PiquePreview.appex
exit 0
POSTINSTALL
/bin/chmod a+x "$PKG_PATH/scripts/postinstall"

# Create the json file for signed munkipkg Pique pkg
/bin/cat << SIGNED_JSONFILE > "$PKG_PATH/build-info.json"
{
  "ownership": "recommended",
  "suppress_bundle_relocation": true,
  "identifier": "io.macadmins.Pique",
  "postinstall_action": "none",
  "distribution_style": true,
  "version": "$AUTOMATED_PIQUE_BUILD",
  "name": "Pique-$AUTOMATED_PIQUE_BUILD.pkg",
  "install_location": "/Applications",
  "signing_info": {
    "identity": "$INSTALLER_SIGNING_IDENTITY",
    "timestamp": true
  }
}
SIGNED_JSONFILE

# Create the signed Pique pkg
python3 "${MP_BINDIR}/munki-pkg-${MP_SHA}/munkipkg" "$PKG_PATH"
PKG_RESULT="$?"
if [ "${PKG_RESULT}" != "0" ]; then
  echo "Could not sign package: ${PKG_RESULT}" 1>&2
else
  # Notarize Pique package
  $XCODE_NOTARY_PATH submit "$PKG_PATH/build/Pique-$AUTOMATED_PIQUE_BUILD.pkg" --keychain-profile "pique" --wait
  $XCODE_STAPLER_PATH staple "$PKG_PATH/build/Pique-$AUTOMATED_PIQUE_BUILD.pkg"
  # Move the Pique signed/notarized pkg
  /bin/mv "$PKG_PATH/build/Pique-$AUTOMATED_PIQUE_BUILD.pkg" "$OUTPUTSDIR"
fi

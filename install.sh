#!/bin/sh

# The original version of this script is licensed under the MIT license.
# See https://github.com/Masterminds/glide/blob/master/LICENSE for more details
# and copyright notice.

PROJECT_NAME="arduino-cli"

# BINDIR represents the local bin location, defaults to ./bin.
LBINDIR=""
DEFAULT_BINDIR="$PWD/bin"

fail() {
	echo "$1"
	exit 1
}

initDestination() {
	if [ -n "$BINDIR" ]; then
		if [ ! -d "$BINDIR" ]; then
			fail "$BINDIR "'($BINDIR)'" folder not found. Please create it before continuing."
		fi
		LBINDIR="$BINDIR"
	else
		if [ ! -d "$DEFAULT_BINDIR" ]; then
		mkdir "$DEFAULT_BINDIR"
		fi
		LBINDIR="$DEFAULT_BINDIR"
	fi
	echo "Installing in $LBINDIR"
}

initArch() {
	ARCH=$(uname -m)
	case $ARCH in
		armv5*) ARCH="armv5";;
		armv6*) ARCH="armv6";;
		armv7*) ARCH="ARMv7";;
		aarch64) ARCH="ARM64";;
		x86) ARCH="32bit";;
		x86_64) ARCH="64bit";;
		i686) ARCH="32bit";;
		i386) ARCH="32bit";;
	esac
	echo "ARCH=$ARCH"
}

initOS() {
	OS=$(uname -s)
	case "$OS" in
		Linux*) OS='Linux' ;;
		Darwin*) OS='macOS' ;;
		MINGW*) OS='Windows';;
		MSYS*) OS='Windows';;
	esac
	echo "OS=$OS"
}

initDownloadTool() {
	if type "curl" > /dev/null; then
		DOWNLOAD_TOOL="curl"
	elif type "wget" > /dev/null; then
		DOWNLOAD_TOOL="wget"
	else
		fail "You need curl or wget as download tool. Please install it first before continuing"
	fi
	echo "Using $DOWNLOAD_TOOL as download tool"
}

get() {
	local url="$2"
	local body
	local httpStatusCode
	echo "Getting $url"
	if [ "$DOWNLOAD_TOOL" = "curl" ]; then
		httpResponse=$(curl -sL --write-out HTTPSTATUS:%{http_code} "$url")
		httpStatusCode=$(echo $httpResponse | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
		body=$(echo "$httpResponse" | sed -e 's/HTTPSTATUS\:.*//g')
	elif [ "$DOWNLOAD_TOOL" = "wget" ]; then
		tmpFile=$(mktemp)
		body=$(wget --server-response --content-on-error -q -O - "$url" 2> $tmpFile || true)
		httpStatusCode=$(cat $tmpFile | awk '/^  HTTP/{print $2}')
	fi
	if [ "$httpStatusCode" != 200 ]; then
		echo "Request failed with HTTP status code $httpStatusCode"
		fail "Body: $body"
	fi
	eval "$1='$body'"
}

getFile() {
	local url="$1"
	local filePath="$2"
	if [ "$DOWNLOAD_TOOL" = "curl" ]; then
		httpStatusCode=$(curl -s -w '%{http_code}' -L "$url" -o "$filePath")
	elif [ "$DOWNLOAD_TOOL" = "wget" ]; then
		body=$(wget --server-response --content-on-error -q -O "$filePath" "$url")
		httpStatusCode=$(cat $tmpFile | awk '/^  HTTP/{print $2}')
	fi
	echo "$httpStatusCode"
}

downloadFile() {
	get TAG_JSON https://api.github.com/repos/arduino/arduino-cli/releases/latest
	TAG=$(echo $TAG_JSON | python -c 'import json,sys;obj=json.load(sys.stdin, strict=False);sys.stdout.write(obj["tag_name"])')
	echo "TAG=$TAG"
	#  arduino-cli_0.4.0-rc1_Linux_64bit.tar.gz
	CLI_DIST="arduino-cli_${TAG}_${OS}_${ARCH}.tar.gz"
	echo "CLI_DIST=$CLI_DIST"
	DOWNLOAD_URL="https://downloads.arduino.cc/arduino-cli/$CLI_DIST"
	CLI_TMP_FILE="/tmp/$CLI_DIST"
	echo "Downloading $DOWNLOAD_URL"
	httpStatusCode=$(getFile "$DOWNLOAD_URL" "$CLI_TMP_FILE")
	if [ "$httpStatusCode" -ne 200 ]; then
		echo "Did not find a release for your system: $OS $ARCH"
		echo "Trying to find a release using the GitHub API."
		LATEST_RELEASE_URL="https://api.github.com/repos/arduino/$PROJECT_NAME/releases/tags/$TAG"
		echo "LATEST_RELEASE_URL=$LATEST_RELEASE_URL"
		get LATEST_RELEASE_JSON $LATEST_RELEASE_URL
		# || true forces this command to not catch error if grep does not find anything
		DOWNLOAD_URL=$(echo "$LATEST_RELEASE_JSON" | grep 'browser_' | cut -d\" -f4 | grep "$CLI_DIST") || true
		if [ -z "$DOWNLOAD_URL" ]; then
			echo "Sorry, we dont have a dist for your system: $OS $ARCH"
			fail "You can request one here: https://github.com/Arduino/$PROJECT_NAME/issues"
		else
			echo "Downloading $DOWNLOAD_URL"
			getFile "$DOWNLOAD_URL" "$CLI_TMP_FILE"
		fi
	fi
}

installFile() {
	CLI_TMP="/tmp/$PROJECT_NAME"
	mkdir -p "$CLI_TMP"
	tar xf "$CLI_TMP_FILE" -C "$CLI_TMP"
	CLI_TMP_BIN="$CLI_TMP/$PROJECT_NAME"
	cp "$CLI_TMP_BIN" "$LBINDIR"
	rm -rf $CLI_TMP
	rm -f $CLI_TMP_FILE
}

bye() {
	result=$?
	if [ "$result" != "0" ]; then
		echo "Failed to install $PROJECT_NAME"
	fi
	exit $result
}

testVersion() {
	set +e
	CLI="$(which $PROJECT_NAME)"
	if [ "$?" = "1" ]; then
		fail "$PROJECT_NAME not found. Did you add "$LBINDIR" to your "'$PATH?'
	fi
	if [ $CLI != "$LBINDIR/$PROJECT_NAME" ]; then
		fail "An existing $PROJECT_NAME was found at $CLI. Please prepend "$LBINDIR" to your "'$PATH'" or remove the existing one."
	fi
	set -e
	CLI_VERSION=$($PROJECT_NAME version)
	echo "$CLI_VERSION installed successfully"
}


# Execution

#Stop execution on any error
trap "bye" EXIT
initDestination
set -e
initArch
initOS
initDownloadTool
downloadFile
installFile
testVersion
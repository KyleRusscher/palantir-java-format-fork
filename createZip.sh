#!/usr/bin/env bash


# Step 1: ./gradlew --no-daemon clean :palantir-java-format:assemble :palantir-java-format-spi:assemble -x test
# Step 2: update VERSION and PREV_VERSION in this file
# step 3: Search "Pin a fixed semantic version for OSSRH publishing of this fork" and update the version to the new version
# Step 3: ./createZip.sh
# Step 4: upload to https://central.sonatype.com/publishing
set -euo pipefail

# Configurable inputs
VERSION=${VERSION:-1.0.2}                 # override: VERSION=1.0.2 ./createZip.sh
PREV_VERSION=${PREV_VERSION:-1.0.1}       # fallback POM/JAR version if 1.0.x not found in m2
KEY=${KEY:-F1118FE9FE02929D2C79CF16AB9C5855AB7411DF}
PASSPHRASE=${PASSPHRASE:-''}
NAMESPACE_PATH=io/github/kylerusscher
MAIN_ARTIFACT=palantir-java-format-fork
SPI_ARTIFACT=palantir-java-format-spi
MAIN_BUILD_NAME=palantir-java-format       # module base name used in build/libs
SPI_BUILD_NAME=palantir-java-format-spi
WORKDIR=$(cd "$(dirname "$0")" && pwd)
UPLOAD_DIR=/Users/krussche/dev/mvn_upload
STAGE=/tmp/central-bundle-${VERSION}-lower

rm -rf "$STAGE"
mkdir -p \
  "$STAGE/$NAMESPACE_PATH/$MAIN_ARTIFACT/$VERSION" \
  "$STAGE/$NAMESPACE_PATH/$SPI_ARTIFACT/$VERSION"

# Helper to copy from m2, then from build/libs if missing
copy_artifacts() {
  local artifact=$1
  local build_base=$2
  local dest_dir=$3

  # POM/JAR from m2 for this VERSION if available
  cp -f "$HOME/.m2/repository/$NAMESPACE_PATH/$artifact/$VERSION/$artifact-$VERSION.pom" "$dest_dir/" 2>/dev/null || true
  cp -f "$HOME/.m2/repository/$NAMESPACE_PATH/$artifact/$VERSION/$artifact-$VERSION.jar" "$dest_dir/" 2>/dev/null || true

  # FALLBACK: use PREV_VERSION for POM/JAR if still missing
  if [[ ! -f "$dest_dir/$artifact-$VERSION.pom" && -f "$HOME/.m2/repository/$NAMESPACE_PATH/$artifact/$PREV_VERSION/$artifact-$PREV_VERSION.pom" ]]; then
    cp -f "$HOME/.m2/repository/$NAMESPACE_PATH/$artifact/$PREV_VERSION/$artifact-$PREV_VERSION.pom" "$dest_dir/$artifact-$VERSION.pom"
    # Update version inside POM
    sed -i '' "s#<version>$PREV_VERSION</version>#<version>$VERSION</version>#g" "$dest_dir/$artifact-$VERSION.pom" || true
  fi
  if [[ ! -f "$dest_dir/$artifact-$VERSION.jar" && -f "$HOME/.m2/repository/$NAMESPACE_PATH/$artifact/$PREV_VERSION/$artifact-$PREV_VERSION.jar" ]]; then
    cp -f "$HOME/.m2/repository/$NAMESPACE_PATH/$artifact/$PREV_VERSION/$artifact-$PREV_VERSION.jar" "$dest_dir/$artifact-$VERSION.jar"
  fi

  # Sources/Javadoc from m2 for this VERSION if available
  cp -f "$HOME/.m2/repository/$NAMESPACE_PATH/$artifact/$VERSION/$artifact-$VERSION-sources.jar" "$dest_dir/" 2>/dev/null || true
  cp -f "$HOME/.m2/repository/$NAMESPACE_PATH/$artifact/$VERSION/$artifact-$VERSION-javadoc.jar" "$dest_dir/" 2>/dev/null || true

  # FALLBACK: copy from build/libs and rename to artifact-VERSION-*.jar
  local build_dir_main="$WORKDIR/$build_base/build/libs"
  if [[ ! -f "$dest_dir/$artifact-$VERSION-sources.jar" && -f "$build_dir_main/$build_base-$VERSION-sources.jar" ]]; then
    cp -f "$build_dir_main/$build_base-$VERSION-sources.jar" "$dest_dir/$artifact-$VERSION-sources.jar"
  fi
  if [[ ! -f "$dest_dir/$artifact-$VERSION-javadoc.jar" && -f "$build_dir_main/$build_base-$VERSION-javadoc.jar" ]]; then
    cp -f "$build_dir_main/$build_base-$VERSION-javadoc.jar" "$dest_dir/$artifact-$VERSION-javadoc.jar"
  fi
}

# Copy artifacts for both modules
copy_artifacts "$MAIN_ARTIFACT" "$MAIN_BUILD_NAME" "$STAGE/$NAMESPACE_PATH/$MAIN_ARTIFACT/$VERSION"
copy_artifacts "$SPI_ARTIFACT" "$SPI_BUILD_NAME" "$STAGE/$NAMESPACE_PATH/$SPI_ARTIFACT/$VERSION"

# Sign and checksum all .pom and .jar files
sign_and_checksum() {
  local dir=$1
  for f in "$dir"/*.pom "$dir"/*.jar; do
    [[ -f "$f" ]] || continue
    gpg --batch --yes --pinentry-mode loopback --passphrase "$PASSPHRASE" --armor --detach-sign --local-user "$KEY" "$f"
    md5 -q "$f" > "$f.md5"
    shasum -a 1 "$f" | awk '{print $1}' > "$f.sha1"
    md5 -q "$f.asc" > "$f.asc.md5"
    shasum -a 1 "$f.asc" | awk '{print $1}' > "$f.asc.sha1"
  done
}

sign_and_checksum "$STAGE/$NAMESPACE_PATH/$MAIN_ARTIFACT/$VERSION"
sign_and_checksum "$STAGE/$NAMESPACE_PATH/$SPI_ARTIFACT/$VERSION"

# Create ZIP
ZIP_OUT="/tmp/pjf-central-upload-${VERSION}-lower.zip"
(
  cd "$STAGE"
  zip -r "$ZIP_OUT" io >/dev/null
)
mkdir -p "$UPLOAD_DIR"
mv -f "$ZIP_OUT" "$UPLOAD_DIR/"

echo "Created: $UPLOAD_DIR/$(basename "$ZIP_OUT")"
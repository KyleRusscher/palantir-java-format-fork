#!/usr/bin/env bash


# Step 1: ./gradlew --no-daemon clean :palantir-java-format:assemble :palantir-java-format-spi:assemble -x test
# Step 2: update VERSION and PREV_VERSION in this file
# step 3: Search "Pin a fixed semantic version for OSSRH publishing of this fork" and update the version to the new version
# Step 4: enter passphrase: kms secret view urn:li:kmsSecret:9bee5c71-397e-495f-8be9-d9f527180553
# Step 5: ./createZip.sh
# Step 6: upload to https://central.sonatype.com/publishing
set -euo pipefail

# Configurable inputs
VERSION=${VERSION:-2.50.1}                 # override: VERSION=1.0.2 ./createZip.sh
PREV_VERSION=${PREV_VERSION:-2.50.1}       # fallback POM/JAR version if 1.0.x not found in m2
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

# Ensure build artifacts and POMs exist for both modules (no signing, no tests)
./gradlew --no-daemon \
  -x test \
  :palantir-java-format:jar :palantir-java-format:sourcesJar :palantir-java-format:javadocJar :palantir-java-format:generatePomFileForMavenJavaPublication \
  :palantir-java-format-spi:jar :palantir-java-format-spi:sourcesJar :palantir-java-format-spi:javadocJar :palantir-java-format-spi:generatePomFileForMavenJavaPublication \
  >/dev/null

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

  # If we got a POM for current VERSION from m2, normalize top-level version and local deps
  if [[ -f "$dest_dir/$artifact-$VERSION.pom" ]]; then
    python3 - "$dest_dir/$artifact-$VERSION.pom" "$VERSION" <<'PY'
import sys, xml.etree.ElementTree as ET
pom_path, new_version = sys.argv[1], sys.argv[2]
ET.register_namespace('', 'http://maven.apache.org/POM/4.0.0')
ns = {'m': 'http://maven.apache.org/POM/4.0.0'}
tree = ET.parse(pom_path)
root = tree.getroot()
ver = root.find('m:version', ns)
if ver is None:
    aid = root.find('m:artifactId', ns)
    elem = ET.Element('{http://maven.apache.org/POM/4.0.0}version')
    elem.text = new_version
    if aid is not None:
        idx = list(root).index(aid)
        root.insert(idx + 1, elem)
    else:
        root.insert(0, elem)
else:
    ver.text = new_version
# fix dependency versions for local modules
deps = root.find('m:dependencies', ns)
if deps is not None:
    for dep in deps.findall('m:dependency', ns):
        gid = dep.find('m:groupId', ns)
        aid = dep.find('m:artifactId', ns)
        ver = dep.find('m:version', ns)
        if gid is not None and aid is not None and gid.text == 'io.github.kylerusscher' and aid.text in (
            'palantir-java-format-spi', 'palantir-java-format-parent'
        ):
            if ver is None:
                ver = ET.SubElement(dep, '{http://maven.apache.org/POM/4.0.0}version')
            ver.text = new_version
tree.write(pom_path, encoding='utf-8', xml_declaration=True)
PY
  fi

  # FALLBACK: use PREV_VERSION for POM/JAR if still missing
  if [[ ! -f "$dest_dir/$artifact-$VERSION.pom" && -f "$HOME/.m2/repository/$NAMESPACE_PATH/$artifact/$PREV_VERSION/$artifact-$PREV_VERSION.pom" ]]; then
    cp -f "$HOME/.m2/repository/$NAMESPACE_PATH/$artifact/$PREV_VERSION/$artifact-$PREV_VERSION.pom" "$dest_dir/$artifact-$VERSION.pom"
    # Update top-level version and fix local dependency versions to current VERSION
    python3 - "$dest_dir/$artifact-$VERSION.pom" "$VERSION" <<'PY'
import sys, xml.etree.ElementTree as ET
pom_path, new_version = sys.argv[1], sys.argv[2]
ET.register_namespace('', 'http://maven.apache.org/POM/4.0.0')
ns = {'m': 'http://maven.apache.org/POM/4.0.0'}
tree = ET.parse(pom_path)
root = tree.getroot()
ver = root.find('m:version', ns)
if ver is None:
    aid = root.find('m:artifactId', ns)
    elem = ET.Element('{http://maven.apache.org/POM/4.0.0}version')
    elem.text = new_version
    if aid is not None:
        idx = list(root).index(aid)
        root.insert(idx + 1, elem)
    else:
        root.insert(0, elem)
else:
    ver.text = new_version
# fix dependency versions for local modules
deps = root.find('m:dependencies', ns)
if deps is not None:
    for dep in deps.findall('m:dependency', ns):
        gid = dep.find('m:groupId', ns)
        aid = dep.find('m:artifactId', ns)
        ver = dep.find('m:version', ns)
        if gid is not None and aid is not None and gid.text == 'io.github.kylerusscher' and aid.text in (
            'palantir-java-format-spi', 'palantir-java-format-parent'
        ):
            if ver is None:
                ver = ET.SubElement(dep, '{http://maven.apache.org/POM/4.0.0}version')
            ver.text = new_version
tree.write(pom_path, encoding='utf-8', xml_declaration=True)
PY
  fi
  if [[ ! -f "$dest_dir/$artifact-$VERSION.jar" && -f "$HOME/.m2/repository/$NAMESPACE_PATH/$artifact/$PREV_VERSION/$artifact-$PREV_VERSION.jar" ]]; then
    cp -f "$HOME/.m2/repository/$NAMESPACE_PATH/$artifact/$PREV_VERSION/$artifact-$PREV_VERSION.jar" "$dest_dir/$artifact-$VERSION.jar"
  fi

  # Sources/Javadoc from m2 for this VERSION if available
  cp -f "$HOME/.m2/repository/$NAMESPACE_PATH/$artifact/$VERSION/$artifact-$VERSION-sources.jar" "$dest_dir/" 2>/dev/null || true
  cp -f "$HOME/.m2/repository/$NAMESPACE_PATH/$artifact/$VERSION/$artifact-$VERSION-javadoc.jar" "$dest_dir/" 2>/dev/null || true

  # FALLBACK: copy from build/libs and rename to artifact-VERSION-*.jar
  local build_dir_main="$WORKDIR/$build_base/build/libs"
  # main jar
  if [[ ! -f "$dest_dir/$artifact-$VERSION.jar" ]]; then
    if [[ -f "$build_dir_main/$build_base-$VERSION.jar" ]]; then
      cp -f "$build_dir_main/$build_base-$VERSION.jar" "$dest_dir/$artifact-$VERSION.jar"
    else
      cand_main=$(ls -1 "$build_dir_main"/*.jar 2>/dev/null | grep -vE '(sources|javadoc)\.jar$' | head -n 1 || true)
      if [[ -n "${cand_main:-}" && -f "$cand_main" ]]; then
        cp -f "$cand_main" "$dest_dir/$artifact-$VERSION.jar"
      fi
    fi
  fi
  # sources
  if [[ ! -f "$dest_dir/$artifact-$VERSION-sources.jar" ]]; then
    if [[ -f "$build_dir_main/$build_base-$VERSION-sources.jar" ]]; then
      cp -f "$build_dir_main/$build_base-$VERSION-sources.jar" "$dest_dir/$artifact-$VERSION-sources.jar"
    else
      cand_src=$(ls -1 "$build_dir_main"/*-sources.jar 2>/dev/null | head -n 1 || true)
      if [[ -n "${cand_src:-}" && -f "$cand_src" ]]; then
        cp -f "$cand_src" "$dest_dir/$artifact-$VERSION-sources.jar"
      fi
    fi
  fi
  # javadoc
  if [[ ! -f "$dest_dir/$artifact-$VERSION-javadoc.jar" ]]; then
    if [[ -f "$build_dir_main/$build_base-$VERSION-javadoc.jar" ]]; then
      cp -f "$build_dir_main/$build_base-$VERSION-javadoc.jar" "$dest_dir/$artifact-$VERSION-javadoc.jar"
    else
      cand_jav=$(ls -1 "$build_dir_main"/*-javadoc.jar 2>/dev/null | head -n 1 || true)
      if [[ -n "${cand_jav:-}" && -f "$cand_jav" ]]; then
        cp -f "$cand_jav" "$dest_dir/$artifact-$VERSION-javadoc.jar"
      fi
    fi
  fi

  # FALLBACK POM: from Gradle publication output
  if [[ ! -f "$dest_dir/$artifact-$VERSION.pom" ]]; then
    local pub_pom="$WORKDIR/$build_base/build/publications/mavenJava/pom-default.xml"
    if [[ -f "$pub_pom" ]]; then
      cp -f "$pub_pom" "$dest_dir/$artifact-$VERSION.pom"
      # Ensure version and local dependency versions match VERSION
      python3 - "$dest_dir/$artifact-$VERSION.pom" "$VERSION" <<'PY'
import sys, xml.etree.ElementTree as ET
pom_path, new_version = sys.argv[1], sys.argv[2]
ET.register_namespace('', 'http://maven.apache.org/POM/4.0.0')
ns = {'m': 'http://maven.apache.org/POM/4.0.0'}
tree = ET.parse(pom_path)
root = tree.getroot()
ver = root.find('m:version', ns)
if ver is None:
    aid = root.find('m:artifactId', ns)
    elem = ET.Element('{http://maven.apache.org/POM/4.0.0}version')
    elem.text = new_version
    if aid is not None:
        idx = list(root).index(aid)
        root.insert(idx + 1, elem)
    else:
        root.insert(0, elem)
else:
    ver.text = new_version
# fix dependency versions for local modules
deps = root.find('m:dependencies', ns)
if deps is not None:
    for dep in deps.findall('m:dependency', ns):
        gid = dep.find('m:groupId', ns)
        aid = dep.find('m:artifactId', ns)
        ver = dep.find('m:version', ns)
        if gid is not None and aid is not None and gid.text == 'io.github.kylerusscher' and aid.text in (
            'palantir-java-format-spi', 'palantir-java-format-parent'
        ):
            if ver is None:
                ver = ET.SubElement(dep, '{http://maven.apache.org/POM/4.0.0}version')
            ver.text = new_version
tree.write(pom_path, encoding='utf-8', xml_declaration=True)
PY
    fi
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
#!/bin/zsh
set -euo pipefail

source_dir="${0:A:h}"
build_dir="$(mktemp -d /tmp/fotobudget-tests.XXXXXXXX)"
trap 'rm -rf -- "$build_dir"' EXIT
for name in FootprintTests SafetyGuardTests SafetyMetadataTests RuntimeSupportTests; do
  xcrun clang -Wall -Wextra -Werror -fobjc-arc -framework Foundation \
    "$source_dir/$name.m" -o "$build_dir/$name"
  "$build_dir/$name"
done
python3 "$source_dir/run-helper-failures.py"
cp "$source_dir/ControlTests.swift" "$build_dir/main.swift"
xcrun clang -Wall -Wextra -Werror -fobjc-arc -framework Foundation \
  "$source_dir/WireFixture.m" -o "$build_dir/WireFixture"
"$build_dir/WireFixture" > "$build_dir/wire.json"
xcrun swiftc -swift-version 6 -warnings-as-errors \
  "$source_dir/../Sources/Shared/ControlProtocol.swift" "$build_dir/main.swift" -o "$build_dir/ControlTests"
"$build_dir/ControlTests" "$build_dir/wire.json"
cp "$source_dir/SetupTests.swift" "$build_dir/main.swift"
xcrun swiftc -swift-version 6 -warnings-as-errors \
  "$source_dir/../Sources/Shared/ControlProtocol.swift" \
  "$source_dir/../Sources/Agent/SetupSupport.swift" "$build_dir/main.swift" -o "$build_dir/SetupTests"
"$build_dir/SetupTests"

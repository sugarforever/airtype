#!/bin/zsh

set -euo pipefail

repo_root=${0:A:h:h}
derived_data_path="$repo_root/.build/xcode-signed-debug"
built_app="$derived_data_path/Build/Products/Debug/Airtype.app"
user_name=$(id -un)
user_home_dir=$(dscl . -read "/Users/$user_name" NFSHomeDirectory | sed -n 's/^NFSHomeDirectory: //p')
user_applications_dir="$user_home_dir/Applications"
installed_app="$user_applications_dir/Airtype Dev.app"
installed_executable="$installed_app/Contents/MacOS/Airtype"
expected_bundle_identifier="com.airtype.app.debug"
expected_team_identifier="58MM7UAN56"

if [[ -z "$user_home_dir" || "$installed_app" != "$user_home_dir/Applications/Airtype Dev.app" ]]; then
    print -u2 "Could not resolve the fixed Airtype Dev installation path."
    exit 1
fi

xcodebuild \
    -project "$repo_root/Airtype.xcodeproj" \
    -scheme Airtype \
    -configuration Debug \
    -derivedDataPath "$derived_data_path" \
    -allowProvisioningUpdates \
    build

codesign --verify --deep --strict "$built_app"
signature_details=$(codesign -dv --verbose=4 "$built_app" 2>&1)
signature_authority=$(print -r -- "$signature_details" | awk -F= '/^Authority=/ && !value { value=$2 } END { print value }')
team_identifier=$(print -r -- "$signature_details" | awk -F= '/^TeamIdentifier=/ && !value { value=$2 } END { print value }')
bundle_identifier=$(print -r -- "$signature_details" | awk -F= '/^Identifier=/ && !value { value=$2 } END { print value }')
if [[ "$signature_authority" != "Apple Development:"* ||
      "$team_identifier" != "$expected_team_identifier" ||
      "$bundle_identifier" != "$expected_bundle_identifier" ]]; then
    print -u2 "Debug build does not have the expected stable development identity."
    print -u2 "Authority: $signature_authority"
    print -u2 "Team: $team_identifier"
    print -u2 "Identifier: $bundle_identifier"
    exit 1
fi

mkdir -p "$user_applications_dir"
staging_dir=$(mktemp -d "$user_applications_dir/.airtype-dev.XXXXXX")
trap 'rm -rf "$staging_dir"' EXIT
staged_app="$staging_dir/Airtype Dev.app"
ditto "$built_app" "$staged_app"
codesign --verify --deep --strict "$staged_app"

if [[ -e "$installed_app" ]]; then
    if [[ ! -d "$installed_app" || ! -f "$installed_app/Contents/Info.plist" ]]; then
        print -u2 "Refusing to replace unexpected item at $installed_app"
        exit 1
    fi
    existing_bundle_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$installed_app/Contents/Info.plist" 2>/dev/null || true)
    if [[ "$existing_bundle_identifier" != "$expected_bundle_identifier" ]]; then
        print -u2 "Refusing to replace app with bundle identifier $existing_bundle_identifier at $installed_app"
        exit 1
    fi

    running_pids=()
    for candidate_pid in $(pgrep -x Airtype 2>/dev/null || true); do
        candidate_command=$(ps -ww -p "$candidate_pid" -o command= | sed 's/^[[:space:]]*//')
        if [[ "$candidate_command" == "$installed_executable" ]]; then
            running_pids+=("$candidate_pid")
        fi
    done
    if (( ${#running_pids[@]} > 0 )); then
        kill "${running_pids[@]}"
        for _ in {1..50}; do
            still_running=false
            for running_pid in "${running_pids[@]}"; do
                if kill -0 "$running_pid" 2>/dev/null; then
                    still_running=true
                    break
                fi
            done
            if [[ "$still_running" == false ]]; then
                break
            fi
            sleep 0.1
        done
        if [[ "$still_running" == true ]]; then
            print -u2 "Airtype Dev did not terminate; refusing to replace the running app."
            exit 1
        fi
    fi

    rm -rf "$installed_app"
fi
mv "$staged_app" "$installed_app"
codesign --verify --deep --strict "$installed_app"

print "Launching $installed_app"
print "Signature: $signature_authority"
print "Team: $team_identifier"
open -n "$installed_app"

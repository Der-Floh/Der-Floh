def basename: split("/") | last;
def text: if type == "number" then tostring elif . == null then "" else . end;
def nexus_id: test("^[0-9A-Za-z-]+$");
def nexus_name: length <= 50 and test("^[a-zA-Z0-9 _'().-]+$");
def workflow_command_text: gsub("%"; "%25") | gsub("\r"; "%0D") | gsub("\n"; "%0A");

def setting_names: ["file-id", "mod-id", "file-name", "file-description"];

def setting_errors:
  $settings | to_entries[] | .key as $package | .value
  | if type != "object" then
      "The settings of \($package) in \($mods_file) are not a JSON object."
    else
      to_entries[]
      | if (.key | IN(setting_names[]) | not) then
          "\($mods_file) has the unknown setting \(.key) for \($package). The settings are \(setting_names | join(", "))."
        elif (.value | type) == "string" or ((.value | type) == "number" and (.key | IN("file-id", "mod-id"))) then
          empty
        else
          "\(.key) of \($package) in \($mods_file) is not a string."
        end
    end;

def zip_identity:
  if has("package") then .
  else . + ((.path | basename | capture("^(?<package>.+?)-(?<version>[0-9]+(\\.[0-9]+){1,3}(-[0-9A-Za-z.-]+)?)\\.zip$")) // {})
  end;

def upload($mods):
  . as $zip
  | ($mods[$zip.package] // {}) as $mod
  | select(($mod["file-id"] // "") != "")
  | {
      "package-path": $zip.path,
      "package-name": $zip.package,
      version: $zip.version,
      "file-id": $mod["file-id"],
      "mod-id": ($mod["mod-id"] // ""),
      "display-name": (if ($mod["file-name"] // "") != "" then "\($mod["file-name"]) v\($zip.version)" else ($zip.path | basename) end),
      description: ($mod["file-description"] // "")
    };

def missing_file_id_notice:
  if $single then
    "file-id is not set, so nothing goes to Nexus Mods. Upload the first version by hand on the mod's Manage Files page, then set the file id; later releases then add their versions to it automatically."
  else
    "\(.path) does not go to Nexus Mods, since \($mods_file) has no file id for \(.package). Upload its first version by hand on the mod's Manage Files page, then add its file id there; later releases then add their versions to it automatically."
  end;

def upload_errors:
  (select(."package-path" | IN($release[]) | not)
    | "\(."package-path") is not in \($package_dir), so it would go to Nexus Mods without being on the release."),
  (select(."file-id" | nexus_id | not)
    | "\(."file-id") is not a Nexus Mods file id. Check the file id of \(."package-name")."),
  (select(."mod-id" != "" and (."mod-id" | nexus_id | not))
    | "\(."mod-id") is not a Nexus Mods mod id. Check the mod id of \(."package-name")."),
  (select($changelog != "" and ."mod-id" == "")
    | "changelog is set but the mod id of \(."package-name") is not, and Nexus Mods needs the mod id to add a changelog."),
  (select(."display-name" | nexus_name | not)
    | "Nexus Mods would refuse \(."display-name") as the name of \(."package-name"): it takes at most 50 letters, digits, spaces and _ ' ( ) . - characters. Shorten its file-name.");

def resolve:
  ($settings | map_values(map_values(text))) as $mods
  | ($zips | map(zip_identity)) as $zips
  | [$zips[] | select(has("package"))] as $identified
  | [$identified[] | upload($mods)] as $uploads
  | {
      uploads: $uploads,
      notices: [$identified[] | select(($mods[.package]["file-id"] // "") == "") | missing_file_id_notice],
      errors: [
        ($release | map(basename) | group_by(.)[] | select(length > 1)
          | "\($package_dir) has \(length) zips named \(.[0]), but a release can only hold one file of a name."),
        ($zips[] | select(has("package") | not)
          | "\(.path) is not named <package-name>-<version>.zip, so it is unclear which version of which mod it is."),
        ($identified | group_by(.package)[] | select(length > 1)
          | "\($mods_dir) has \(length) zips of \(.[0].package): \(map(.path | basename) | join(", ")). Leave only the one to release."),
        ($mods | keys[] | . as $package | select($identified | any(.package == $package) | not)
          | "\($mods_file) has settings for \($package), but \($mods_dir) has no zip of it."),
        ($uploads[] | upload_errors)
      ]
    };

[setting_errors] as $errors
| if $errors == [] then resolve else {uploads: [], notices: [], errors: $errors} end
| .notices |= map(workflow_command_text)
| .errors |= map(workflow_command_text)

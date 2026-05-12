#!/usr/bin/env bash
# App Name: Node_Validator (keyed mapping + predicate-safe XPaths)
# Purpose: Map parameters rows to XML files by a stable key and compare user-specified label XPaths (supports predicates for repeated nodes)
# Author: Eshan Gurusinghe
# Contact: Email:engurusinghe91@gmail.com
# Version: 1.0 - checking parameters hardcoded version
# 1.1 - checking parameters can be imported as text file
# 1.2 - dynamic to validate any XML format, map XML parameters dynamically, check XML well-formedness

set -o pipefail

# --- Requirements: Bash >= 4 for associative arrays ---
if (( BASH_VERSINFO[0] < 4 )); then
  echo "ERROR: ⚠️ This script requires Bash 4 or newer." >&2
  exit 1
fi

# --- Helpers ---
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

validate_xml() {
  local file="$1"
  if command -v xmlstarlet >/dev/null 2>&1; then
    xmlstarlet val -e -q "$file" 2>/dev/null
    return $?
  elif command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$file" 2>/dev/null
    return $?
  else
    echo "INFO: ℹ️ Neither 'xmlstarlet' nor 'xmllint' is installed; skipping strict XML validation for $file." >&2
    return 0
  fi
}

has_xml_tool() {
  if command -v xmlstarlet >/dev/null 2>&1; then
    return 0
  elif command -v xmllint >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

extract_value_xpath() {
  local file="$1" xpath="$2"
  if command -v xmlstarlet >/dev/null 2>&1; then
    # xmlstarlet prints node string value; head -n1 to take first
    xmlstarlet sel -t -v "$xpath" -n "$file" 2>/dev/null | head -n1
    return 0
  elif command -v xmllint >/dev/null 2>&1; then
    xmllint --xpath "string($xpath)" "$file" 2>/dev/null | head -n1
    return 0
  else
    return 1
  fi
}

# --- User Inputs ---
read -r -p "Enter path to XML location (directory with .xml files OR a single .xml file): " XML_LOC
XML_LOC="${XML_LOC:-./}"

if [[ -d "$XML_LOC" ]]; then
  mapfile -t XML_FILES < <(find "$XML_LOC" -type f -name '*.xml' | sort)
elif [[ -f "$XML_LOC" ]]; then
  if [[ "$XML_LOC" != *.xml ]]; then
    echo "ERROR: ⚠️ Provided file is not .xml: $XML_LOC" >&2
    exit 1
  fi
  XML_FILES=("$XML_LOC")
else
  echo "ERROR: ⚠️ Path not found: $XML_LOC" >&2
  exit 1
fi

if (( ${#XML_FILES[@]} == 0 )); then
  echo "ERROR: ⚠️ No .xml files found at '$XML_LOC'." >&2
  exit 1
fi

echo "Discovered ${#XML_FILES[@]} XML file(s)."

read -r -p "Enter path to parameter text file (should be a .txt with TAB-separated): " MAP_FILE
if [[ -z "$MAP_FILE" ]]; then
  echo "ERROR: ⚠️ Parameters file path is required." >&2
  exit 1
fi
if [[ ! -f "$MAP_FILE" ]]; then
  echo "ERROR: ⚠️ File not found: $MAP_FILE" >&2
  exit 1
fi
if [[ "$MAP_FILE" != *.txt ]]; then
  echo "ERROR: ⚠️ Parameters file must have .txt extension." >&2
  exit 1
fi
if command -v file >/dev/null 2>&1; then
  mime_type=$(file --mime-type -b "$MAP_FILE" 2>/dev/null)
  case "$mime_type" in
    text/*) ;;
    *) echo "ERROR: ⚠️ '$MAP_FILE' MIME type '$mime_type' is not text/*." >&2; exit 1;;
  esac
fi

read -r -p "How many parameter points to check in the XML (Number should be similler to parameter file's column count)? " NUM_LABELS
if [[ -z "$NUM_LABELS" || ! "$NUM_LABELS" =~ ^[0-9]+$ || "$NUM_LABELS" -le 0 ]]; then
  echo "ERROR: ⚠️ Number of labels must be a positive integer." >&2
  exit 1
fi

# Collect labels/XPaths
declare -a LABEL_NAMES
declare -a LABEL_XPATHS
for (( i=1; i<=NUM_LABELS; i++ )); do
  read -r -p "Label $i friendly name: " lname
  [[ -z "$lname" ]] && lname="Label $i"
  read -r -p "Label $i XPath (supports predicates, EX:- /Entity/EntityInfo/SubjectField[Type='COMMON_NAME']/Value): " lxpath
  if [[ -z "$lxpath" ]]; then
    echo "ERROR: ⚠️ XPath for Label $i cannot be empty." >&2
    exit 1
  fi
  LABEL_NAMES+=("$lname")
  LABEL_XPATHS+=("$lxpath")
done

# Key mapping prompts
read -r -p "Which column index (1-based) in the parameters file is the KEY to match XMLs? (default 1) " KEY_COL
KEY_COL="${KEY_COL:-1}"
if [[ ! "$KEY_COL" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: ⚠️ Key column index must be a positive integer." >&2
  exit 1
fi

read -r -p "XPath to extract the KEY from XML (default /Entities/Entity/EntityInfo/Name): " XML_KEY_XPATH
XML_KEY_XPATH="${XML_KEY_XPATH:-/Entities/Entity/EntityInfo/Name}"

# Tool availability
if ! has_xml_tool; then
  echo "ERROR: ⚠️ Neither 'xmlstarlet' nor 'xmllint' is installed. Please install one of them." >&2
  exit 1
fi

# --- Load parameters and build map[key] -> row ---
declare -A ROW_MAP
declare -A ROW_SEEN
declare -a PARAM_KEYS
line_no=0
while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
  line_no=$((line_no+1))
  trimmed="$(trim "$raw_line")"
  [[ -z "$trimmed" ]] && continue
  [[ "$trimmed" =~ ^# ]] && continue

  IFS=$'\t' read -r -a cols <<< "$raw_line"
  if (( ${#cols[@]} != NUM_LABELS )); then
    echo "ERROR: ⚠️ Line $line_no has ${#cols[@]} column(s); expected $NUM_LABELS (TAB-separated)." >&2
    exit 1
  fi
  # Trim each column
  cleaned=()
  for c in "${cols[@]}"; do
    cleaned+=("$(trim "$c")")
  done

  # Extract key (1-based index)
  key_idx=$((KEY_COL-1))
  key="${cleaned[$key_idx]}"
  if [[ -z "$key" ]]; then
    echo "ERROR: ⚠️ Line $line_no: key column $KEY_COL is empty." >&2
    exit 1
  fi

  row_str=$(printf "%s\t" "${cleaned[@]}")
  row_str="${row_str%$'\t'}"

  if [[ -n "${ROW_SEEN[$key]}" ]]; then
    echo "WARN: Duplicate key '$key' found at line $line_no. Overwriting previous entry." >&2
  fi
  ROW_MAP["$key"]="$row_str"
  ROW_SEEN["$key"]=1
  PARAM_KEYS+=("$key")

done < "$MAP_FILE"

if (( ${#PARAM_KEYS[@]} == 0 )); then
  echo "ERROR: ⚠️ No valid rows loaded from '$MAP_FILE'." >&2
  exit 1
fi

# --- Process XML files ---
pass_files=0
fail_files=0

declare -a UNMATCHED_XML

echo
for file in "${XML_FILES[@]}"; do
  if ! validate_xml "$file"; then
    echo "FAIL: ⚠️ $file: Invalid XML (not well-formed); skipping."
    fail_files=$((fail_files+1))
    continue
  fi

  xml_key_raw="$(extract_value_xpath "$file" "$XML_KEY_XPATH")"
  xml_key="$(trim "$xml_key_raw")"

  if [[ -z "$xml_key" ]]; then
    echo "WARN: ℹ️ $file: XML KEY not found via XPath '$XML_KEY_XPATH'. Skipping file."
    UNMATCHED_XML+=("$file")
    continue
  fi

  row="${ROW_MAP[$xml_key]}"
  if [[ -z "$row" ]]; then
    echo "WARN: ℹ️ $file: No parameters row found for key '$xml_key'. Skipping file."
    UNMATCHED_XML+=("$file")
    continue
  fi

  IFS=$'\t' read -r -a cols <<< "$row"
  all_ok=true
  echo "Checking file: $file (key='$xml_key')"
  for (( j=0; j<NUM_LABELS; j++ )); do
    label_name="${LABEL_NAMES[$j]}"
    xpath="${LABEL_XPATHS[$j]}"
    expected="${cols[$j]}"

    actual_raw="$(extract_value_xpath "$file" "$xpath")"
    actual="$(trim "$actual_raw")"

    if [[ "$actual" == "$expected" ]]; then
      echo "  OK: [$label_name] matches expected ('$expected')"
    else
      echo "  MISMATCH: [$label_name]"
      echo "    Expected: '${expected:-<none>}'"
      echo "    Found:    '${actual:-<none>}'"
      all_ok=false
    fi
  done

  if $all_ok; then
    echo "RESULT: $file: ✅ All checks passed."
    pass_files=$((pass_files+1))
  else
    echo "RESULT: $file: ❌ One or more checks failed."
    fail_files=$((fail_files+1))
  fi
  echo

done

# --- Summary and unmatched items ---
# Find parameter keys not matched to any XML
declare -A MATCHED_KEYS
for file in "${XML_FILES[@]}"; do
  xml_key_raw="$(extract_value_xpath "$file" "$XML_KEY_XPATH")"
  xml_key="$(trim "$xml_key_raw")"
  [[ -n "$xml_key" ]] && MATCHED_KEYS["$xml_key"]=1
done

declare -a UNMATCHED_PARAM_KEYS
for k in "${PARAM_KEYS[@]}"; do
  if [[ -z "${MATCHED_KEYS[$k]}" ]]; then
    UNMATCHED_PARAM_KEYS+=("$k")
  fi
done

echo "Summary:"
echo "  ⏭️ Total XML files considered: ${#XML_FILES[@]}"
echo "  ✅ Passed: $pass_files"
echo "  ❌ Failed: $fail_files"

if (( ${#UNMATCHED_XML[@]} > 0 )); then
  echo "  Unmatched XML files (no key or no row):"
  for f in "${UNMATCHED_XML[@]}"; do echo "    - $f"; done
fi

if (( ${#UNMATCHED_PARAM_KEYS[@]} > 0 )); then
  echo "  Unmatched parameter keys (no corresponding XML):"
  for k in "${UNMATCHED_PARAM_KEYS[@]}"; do echo "    - $k"; done
fi

# End of the script

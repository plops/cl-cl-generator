#!/usr/bin/env sh
set -eu

script_name=$(basename "$0")
image_name=${IMAGE_NAME:-my-ai-env:latest}
volume_name=${CARGO_CACHE_VOLUME:-my-ai-env-cargo-cache}
remove_volume=0
prune_dangling=0
verbose=0
list_other_images_sort=
delete_other_images=""
suggest_cleanup=0

usage() {
  cat <<EOF
Usage: $script_name [OPTIONS]

Clean up Docker containers and images for this example.

Default behavior:
  1. Stop running containers created from \$IMAGE_NAME.
  2. Remove all containers created from \$IMAGE_NAME.
  3. Remove the image tag \$IMAGE_NAME.

Options:
  --remove-volume  Also remove the Cargo cache volume (\$CARGO_CACHE_VOLUME).
  --prune-dangling Remove dangling images after targeted cleanup.
  --suggest-cleanup
                  Show suggested cleanup commands with estimated reclaimable
                  space, then exit without deleting anything.
  --list-other-images SORT
                  List local images other than \$IMAGE_NAME sorted by SORT.
                  SORT must be 'size' or 'age'.
  --delete-other-image REF
                  Remove another local image by reference or image ID.
                  May be specified more than once.
  -v, --verbose    Print the Docker commands before running them.
  -h, --help       Show this help text and exit.

Environment:
  IMAGE_NAME           Override the image name. Default: my-ai-env:latest
  CARGO_CACHE_VOLUME   Override the named cargo cache volume.
                       Default: my-ai-env-cargo-cache
EOF
}

log_cmd() {
  if [ "$verbose" -eq 1 ]; then
    echo "+ $*" >&2
  fi
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

format_bytes() {
  bytes=${1:-0}
  if have_cmd numfmt; then
    numfmt --to=iec-i --suffix=B "$bytes" 2>/dev/null || echo "${bytes}B"
  else
    echo "${bytes}B"
  fi
}

image_size_bytes() {
  ref=$1
  docker image inspect --format '{{.VirtualSize}}' "$ref" 2>/dev/null ||
    docker image inspect --format '{{.Size}}' "$ref" 2>/dev/null ||
    echo 0
}

volume_size_bytes() {
  volume=$1

  if ! docker volume inspect "$volume" >/dev/null 2>&1; then
    echo 0
    return
  fi

  mountpoint=$(docker volume inspect --format '{{.Mountpoint}}' "$volume" 2>/dev/null || echo "")
  if [ -z "$mountpoint" ] || [ ! -d "$mountpoint" ]; then
    echo 0
    return
  fi

  if du -sb "$mountpoint" >/dev/null 2>&1; then
    du -sb "$mountpoint" 2>/dev/null | awk '{print $1}'
  else
    du -sk "$mountpoint" 2>/dev/null | awk '{print $1 * 1024}'
  fi
}

estimate_dangling_bytes() {
  docker image ls -f dangling=true -q --no-trunc |
  sort -u |
  while IFS= read -r image_id; do
    [ -n "$image_id" ] || continue
    image_size_bytes "$image_id"
  done |
  awk '{sum += $1} END {print sum + 0}'
}

print_cleanup_suggestions() {
  target_image_bytes=0
  volume_bytes=0
  dangling_bytes=0

  if docker image inspect "$image_name" >/dev/null 2>&1; then
    target_image_bytes=$(image_size_bytes "$image_name")
  fi

  if docker volume inspect "$volume_name" >/dev/null 2>&1; then
    volume_bytes=$(volume_size_bytes "$volume_name")
  fi

  dangling_bytes=$(estimate_dangling_bytes)

  base_total=$target_image_bytes
  with_dangling_total=$(awk "BEGIN {print $base_total + $dangling_bytes}")
  with_volume_total=$(awk "BEGIN {print $base_total + $volume_bytes}")
  full_total=$(awk "BEGIN {print $base_total + $volume_bytes + $dangling_bytes}")

  echo "Suggested cleanup commands (estimated reclaimable space):"
  printf '  %s\n' "$script_name"
  printf '    %s\n' "$(format_bytes "$base_total")"
  printf '  %s --prune-dangling\n' "$script_name"
  printf '    %s\n' "$(format_bytes "$with_dangling_total")"
  printf '  %s --remove-volume\n' "$script_name"
  printf '    %s\n' "$(format_bytes "$with_volume_total")"
  printf '  %s --remove-volume --prune-dangling\n' "$script_name"
  printf '    %s\n' "$(format_bytes "$full_total")"

  if [ "$target_image_bytes" -eq 0 ] && [ "$volume_bytes" -eq 0 ] && [ "$dangling_bytes" -eq 0 ]; then
    echo "  No matching image, volume, or dangling images were found."
  fi

  echo
  echo "Notes:"
  echo "  Estimates are approximate because Docker layers may be shared."
  echo "  Use --list-other-images size to inspect large tagged images outside this example."
}

append_delete_other_image() {
  ref=$1
  if [ -z "$delete_other_images" ]; then
    delete_other_images=$ref
  else
    delete_other_images=$delete_other_images'
'$ref
  fi
}

print_other_images() {
  sort_mode=$1
  target_image_id=

  if docker image inspect "$image_name" >/dev/null 2>&1; then
    target_image_id=$(docker image inspect --format '{{.Id}}' "$image_name")
  fi

  tmp_file=$(mktemp)
  trap 'rm -f "$tmp_file"' EXIT INT TERM HUP

  docker image ls --no-trunc --format '{{.Repository}}:{{.Tag}}	{{.ID}}' |
  while IFS='	' read -r ref image_id; do
    [ -n "$ref" ] || continue
    [ "$ref" = "<none>:<none>" ] && continue
    if [ -n "$target_image_id" ] && docker image inspect "$ref" >/dev/null 2>&1; then
      current_id=$(docker image inspect --format '{{.Id}}' "$ref")
      [ "$current_id" = "$target_image_id" ] && continue
    fi

    created_epoch=$(docker image inspect --format '{{.Created}}' "$ref" | sed 's/\..*Z$/Z/' | xargs -I{} date -u -d "{}" +%s 2>/dev/null || echo 0)
    created_human=$(docker image inspect --format '{{.Created}}' "$ref" | sed 's/\..*Z$/Z/')
    size_bytes=$(docker image inspect --format '{{.Size}}' "$ref" 2>/dev/null || echo 0)
    virtual_size=$(docker image inspect --format '{{.VirtualSize}}' "$ref" 2>/dev/null || echo 0)
    printf '%s\t%s\t%s\t%s\t%s\n' "$size_bytes" "$created_epoch" "$ref" "$created_human" "$virtual_size"
  done > "$tmp_file"

  if [ ! -s "$tmp_file" ]; then
    echo "No other tagged images found."
    rm -f "$tmp_file"
    trap - EXIT INT TERM HUP
    return
  fi

  if [ "$sort_mode" = "size" ]; then
    sort -nr -k1,1 "$tmp_file"
  else
    sort -n -k2,2 "$tmp_file"
  fi |
  while IFS='	' read -r size_bytes created_epoch ref created_human virtual_size; do
    size_human=$(numfmt --to=iec-i --suffix=B "$virtual_size" 2>/dev/null || echo "$virtual_size")
    printf '%-40s  %-10s  %s\n' "$ref" "$size_human" "$created_human"
  done

  rm -f "$tmp_file"
  trap - EXIT INT TERM HUP
}

delete_other_images_now() {
  target_image_id=

  if docker image inspect "$image_name" >/dev/null 2>&1; then
    target_image_id=$(docker image inspect --format '{{.Id}}' "$image_name")
  fi

  printf '%s\n' "$delete_other_images" |
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    if ! docker image inspect "$ref" >/dev/null 2>&1; then
      echo "Other image not found: $ref" >&2
      continue
    fi

    if [ -n "$target_image_id" ]; then
      current_id=$(docker image inspect --format '{{.Id}}' "$ref")
      if [ "$current_id" = "$target_image_id" ]; then
        echo "Refusing to delete target image via --delete-other-image: $ref" >&2
        continue
      fi
    fi

    log_cmd docker rmi "$ref"
    docker rmi "$ref"
  done
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --remove-volume)
      remove_volume=1
      ;;
    --prune-dangling)
      prune_dangling=1
      ;;
    --suggest-cleanup)
      suggest_cleanup=1
      ;;
    --list-other-images)
      shift
      if [ "$#" -eq 0 ]; then
        echo "Missing value for --list-other-images" >&2
        exit 1
      fi
      case "$1" in
        size|age)
          list_other_images_sort=$1
          ;;
        *)
          echo "Invalid sort mode for --list-other-images: $1" >&2
          echo "Expected 'size' or 'age'." >&2
          exit 1
          ;;
      esac
      ;;
    --delete-other-image)
      shift
      if [ "$#" -eq 0 ]; then
        echo "Missing value for --delete-other-image" >&2
        exit 1
      fi
      append_delete_other_image "$1"
      ;;
    -v|--verbose)
      verbose=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Use -h for usage." >&2
      exit 1
      ;;
  esac
  shift
done

if [ "$suggest_cleanup" -eq 1 ]; then
  print_cleanup_suggestions
  exit 0
fi

running_container_ids=$(docker ps -q --filter "ancestor=$image_name")
all_container_ids=$(docker ps -aq --filter "ancestor=$image_name")

if [ -n "$running_container_ids" ]; then
  log_cmd docker stop $running_container_ids
  # shellcheck disable=SC2086
  docker stop $running_container_ids
else
  echo "No running containers found for image $image_name."
fi

if [ -n "$all_container_ids" ]; then
  log_cmd docker rm $all_container_ids
  # shellcheck disable=SC2086
  docker rm $all_container_ids
else
  echo "No containers found for image $image_name."
fi

if docker image inspect "$image_name" >/dev/null 2>&1; then
  log_cmd docker rmi "$image_name"
  docker rmi "$image_name"
else
  echo "Image not found: $image_name"
fi

if [ "$remove_volume" -eq 1 ]; then
  if docker volume inspect "$volume_name" >/dev/null 2>&1; then
    log_cmd docker volume rm "$volume_name"
    docker volume rm "$volume_name"
  else
    echo "Volume not found: $volume_name"
  fi
fi

if [ "$prune_dangling" -eq 1 ]; then
  log_cmd docker image prune -f
  docker image prune -f
fi

if [ -n "$list_other_images_sort" ]; then
  print_other_images "$list_other_images_sort"
fi

if [ -n "$delete_other_images" ]; then
  delete_other_images_now
fi

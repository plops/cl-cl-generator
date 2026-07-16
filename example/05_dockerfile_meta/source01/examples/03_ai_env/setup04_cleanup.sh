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

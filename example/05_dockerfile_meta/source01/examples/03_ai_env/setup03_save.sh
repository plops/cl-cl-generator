docker save my-ai-env:latest -o /dev/shm/my-ai-env.tar
zstd /dev/shm/my-ai-env.tar
# docker load -i /dev/shm/my-ai-env.tar.zst

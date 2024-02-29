FROM alpine:latest

RUN apk add --no-cache make restic rclone

COPY bin/* /bin

ENTRYPOINT ["/bin/entrypoint.sh"]

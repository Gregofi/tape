FROM alpine:latest

RUN apk add --no-cache openssh

COPY bin/* /bin

ENTRYPOINT ["/bin/entrypoint.sh"]

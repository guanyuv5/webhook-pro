FROM alpine:latest

ADD webhook-pro /webhook-pro
ENTRYPOINT ["./webhook-pro"]

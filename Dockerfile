FROM alpine:latest AS reseed

RUN apk --no-cache add ca-certificates curl tor

COPY --chmod=0755 container/fetch_reseed.sh /usr/local/bin/fetch-reseed

ENTRYPOINT ["/usr/local/bin/fetch-reseed"]

FROM alpine:latest AS router

LABEL maintainer="Chris Bensch <chris.bensch@gmail.com>"

RUN apk --no-cache add i2pd

COPY config/i2pd.conf config/subscriptions.txt config/tunnels.conf container/start_i2pd.sh /etc/i2pd/

ENTRYPOINT ["/etc/i2pd/start_i2pd.sh"]

# Mount a dedicated data directory at /var/lib/i2pd to retain router state.

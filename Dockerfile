FROM docker.io/library/alpine:latest AS builder

# Install Zig
RUN apk update && \
  apk add --no-cache curl xz && \
  curl https://ziglang.org/download/0.16.0/zig-x86_64-linux-0.16.0.tar.xz | \
  tar -xJC /usr/local && \
  ln -s /usr/local/zig-x86_64-linux-0.16.0/zig /usr/local/bin/zig

WORKDIR /app
COPY build.zig build.zig.zon ./
COPY src/ src/
RUN zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-linux-musl

# FROM docker.io/library/alpine:latest
# COPY --from=builder /app/zig-out/bin/weather_monitoring_iot_system /weather_monitoring_iot_system
# RUN adduser -D -H zigiotuser
# USER zigiotuser

FROM scratch
COPY --from=builder /app/zig-out/bin/weather_monitoring_iot_system /weather_monitoring_iot_system

EXPOSE 8080
CMD ["/weather_monitoring_iot_system"]

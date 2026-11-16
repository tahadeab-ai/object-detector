# Stage 1: Build binary using official Go toolchain
FROM golang:1.22-alpine AS builder

WORKDIR /app

# Download dependencies
COPY go.mod ./
RUN go mod tidy || true

# Copy source and build minimal statically-linked binary
COPY main.go ./
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-w -s" -o yolo-telemetry .

# Stage 2: Distroless minimal runner container
FROM alpine:3.19

RUN addgroup -S appgroup && adduser -S nonroot -G appgroup

WORKDIR /home/nonroot

COPY --from=builder /app/yolo-telemetry /usr/local/bin/yolo-telemetry

USER nonroot

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/yolo-telemetry"]

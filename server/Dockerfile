FROM golang:1.24-alpine AS builder

WORKDIR /app
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o cashew-sync .

FROM alpine:3.20
RUN apk add --no-cache ca-certificates
WORKDIR /app
COPY --from=builder /app/cashew-sync .
RUN mkdir -p /data/backups

ENV PORT=8085
ENV BACKUP_DIR=/data/backups

EXPOSE 8085
VOLUME /data/backups

CMD ["./cashew-sync"]

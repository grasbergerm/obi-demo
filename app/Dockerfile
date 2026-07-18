# Shared multi-stage Dockerfile for all three demo services.
# Build with:  docker build --build-arg SERVICE=<frontend|backend|backend-sdk> -t <tag> app/
FROM golang:1.24-alpine AS build
ARG SERVICE
WORKDIR /src
COPY ${SERVICE}/ .
RUN go mod tidy && CGO_ENABLED=0 go build -o /out/app .

# A static binary in a scratch image: no shell, no distro, nothing for an
# agent to exec into and OBI still instruments it from outside the container.
FROM scratch
COPY --from=build /out/app /app
EXPOSE 8080
ENTRYPOINT ["/app"]

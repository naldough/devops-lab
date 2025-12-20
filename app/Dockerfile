# Build
FROM golang:1.22 AS build
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY . .
ARG VERSION=dev
ARG COMMIT_SHA=unknown
ARG BUILD_TIME=unknown
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags "\
  -X main.version=${VERSION} \
  -X main.commitSHA=${COMMIT_SHA} \
  -X main.buildTime=${BUILD_TIME}" \
  -o /out/api .

# Run
FROM gcr.io/distroless/static-debian12
COPY --from=build /out/api /api
EXPOSE 8080
USER 65532:65532
ENTRYPOINT ["/api"]

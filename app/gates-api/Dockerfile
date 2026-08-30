FROM golang:1.25-bookworm AS build

WORKDIR /src

COPY go.mod ./
COPY main.go ./

RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /gates-api .

FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=build /gates-api /gates-api

USER nonroot:nonroot

EXPOSE 8080

ENTRYPOINT ["/gates-api"]

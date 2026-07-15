FROM swift:6.0-jammy AS build
WORKDIR /build

COPY Package.swift ./
RUN swift package resolve

COPY Sources ./Sources
RUN swift build -c release

FROM swift:6.0-jammy-slim
WORKDIR /app

COPY --from=build /build/.build/release/App ./App
COPY Public ./Public

RUN mkdir -p /app/Data

ENV DATA_DIR=/app/Data
EXPOSE 8080

ENTRYPOINT ["./App"]

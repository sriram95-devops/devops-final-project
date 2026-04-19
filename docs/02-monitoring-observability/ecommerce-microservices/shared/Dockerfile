# Multi-stage Dockerfile — used for all 8 microservices.
# Java 21 + Spring Boot 3 + Gradle 8.5
# SERVICE_NAME and APP_ENV are injected at runtime via Kubernetes env vars — DevOps controls these.

# ── Stage 1: Build ────────────────────────────────────────────────────────────
FROM eclipse-temurin:21-jdk-alpine AS builder

WORKDIR /build

# Copy Gradle wrapper first (layer cache — only re-downloads if wrapper changes)
COPY gradle/wrapper/gradle-wrapper.properties gradle/wrapper/
COPY gradlew .
RUN chmod +x gradlew

# Copy build scripts and download dependencies (cached layer)
COPY build.gradle settings.gradle ./
RUN ./gradlew dependencies --no-daemon -q || true

# Copy source and build the fat JAR
COPY src ./src
RUN ./gradlew bootJar --no-daemon -q

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM eclipse-temurin:21-jre-alpine AS runtime

WORKDIR /app

# Security: run as non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Copy only the executable JAR from the build stage
COPY --from=builder /build/build/libs/app.jar app.jar
RUN chown appuser:appgroup app.jar

USER appuser

EXPOSE 8080

# Graceful shutdown support
STOPSIGNAL SIGTERM

HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=3 \
  CMD wget -qO- http://localhost:8080/actuator/health || exit 1

# JVM flags: container-aware memory limits + fast startup
ENTRYPOINT ["java", \
  "-XX:+UseContainerSupport", \
  "-XX:MaxRAMPercentage=75.0", \
  "-XX:+ExitOnOutOfMemoryError", \
  "-jar", "app.jar"]

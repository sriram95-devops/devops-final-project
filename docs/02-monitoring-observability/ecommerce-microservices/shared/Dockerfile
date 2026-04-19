# Dockerfile — used for all 8 microservices.
# Java 21 + Spring Boot 3 + Gradle 8.5
# Pre-built JAR (built locally via: gradle bootJar --no-daemon)
# SERVICE_NAME and APP_ENV are injected at runtime via Kubernetes env vars.

FROM eclipse-temurin:21-jre-alpine AS runtime

WORKDIR /app

# Security: run as non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Copy the pre-built fat JAR (produced by: gradle bootJar)
COPY build/libs/app.jar app.jar
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

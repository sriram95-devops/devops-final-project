package com.ecommerce.controller;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.concurrent.TimeUnit;

/**
 * Single controller shared by all 8 microservices.
 * SERVICE_NAME and APP_ENV are injected from Kubernetes env vars — DevOps controls these.
 * Developers write the code once; DevOps controls what each pod reports.
 */
@RestController
public class AppController {

    private final String serviceName;
    private final String appEnv;
    private final Random random = new Random();

    // Micrometer metrics — automatically exported in Prometheus format at /actuator/prometheus
    private final Counter errorCounter;
    private final Timer slowTimer;

    public AppController(
            @Value("${app.service-name:unknown-service}") String serviceName,
            @Value("${app.env:dev}") String appEnv,
            MeterRegistry registry) {

        this.serviceName = serviceName;
        this.appEnv      = appEnv;

        // Custom counter for simulated errors (labelled with service + env)
        this.errorCounter = Counter.builder("app_simulated_errors_total")
                .description("Total simulated errors triggered")
                .tag("service", serviceName)
                .tag("env", appEnv)
                .register(registry);

        // Custom timer for slow endpoint
        this.slowTimer = Timer.builder("app_slow_request_duration_seconds")
                .description("Duration of slow endpoint calls")
                .tag("service", serviceName)
                .tag("env", appEnv)
                .register(registry);
    }

    // ── Routes ────────────────────────────────────────────────────────────────

    /** Root — basic service info */
    @GetMapping("/")
    public Map<String, Object> root() {
        return Map.of(
                "service",   serviceName,
                "env",       appEnv,
                "status",    "running",
                "timestamp", Instant.now().toString()
        );
    }

    /** Normal API response */
    @GetMapping("/api/data")
    public Map<String, Object> data() {
        return Map.of(
                "service", serviceName,
                "data",    Map.of("items", List.of("item1", "item2", "item3"), "total", 3)
        );
    }

    /**
     * Simulates a slow operation (300ms – 2300ms).
     * Used in latency scenario testing.
     */
    @GetMapping("/api/slow")
    public Map<String, Object> slow() throws InterruptedException {
        long delayMs = 300 + (long)(random.nextDouble() * 2000);
        long start = System.nanoTime();
        Thread.sleep(delayMs);
        slowTimer.record(System.nanoTime() - start, TimeUnit.NANOSECONDS);
        return Map.of("service", serviceName, "message", "slow response simulated", "delayMs", delayMs);
    }

    /**
     * Simulates errors — 50% chance of HTTP 500.
     * Used in error rate scenario testing.
     */
    @GetMapping("/api/error")
    public Map<String, Object> error(jakarta.servlet.http.HttpServletResponse response) {
        if (random.nextDouble() < 0.5) {
            errorCounter.increment();
            response.setStatus(500);
            return Map.of("service", serviceName, "error", "Simulated internal error");
        }
        return Map.of("service", serviceName, "message", "Success (no error this time)");
    }

    /**
     * CPU stress — spins for 500ms.
     * Used in resource utilisation scenario testing.
     */
    @GetMapping("/api/stress")
    public Map<String, Object> stress() {
        long end = System.currentTimeMillis() + 500;
        while (System.currentTimeMillis() < end) { /* busy wait */ }
        return Map.of("service", serviceName, "message", "CPU stress completed");
    }

    // Health and readiness probes are provided by Spring Actuator at /actuator/health
    // Prometheus metrics are at /actuator/prometheus — no extra code needed
}

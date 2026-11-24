package com.yourname.donation;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.testcontainers.containers.PostgreSQLContainer;

/** PostgreSQL 16 thật cho integration test; Spring Boot tự nối datasource nhờ @ServiceConnection. */
@TestConfiguration(proxyBeanMethods = false)
public class TestcontainersConfiguration {

    static {
        // Chạy test từ IDE (không qua Maven) vẫn dùng UTC, tránh lỗi múi giờ "Asia/Saigon" của PostgreSQL.
        java.util.TimeZone.setDefault(java.util.TimeZone.getTimeZone("UTC"));
    }

    @Bean
    @ServiceConnection
    PostgreSQLContainer<?> postgresContainer() {
        return new PostgreSQLContainer<>("postgres:16");
    }
}

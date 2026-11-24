package com.yourname.donation;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

import java.util.TimeZone;

@SpringBootApplication
public class DonationApplication {

    public static void main(String[] args) {
        // Mọi thời điểm lưu ở UTC (spec §9.1). Cũng tránh lỗi PostgreSQL từ chối tên múi giờ cũ
        // của JVM như "Asia/Saigon" ("invalid value for parameter TimeZone").
        TimeZone.setDefault(TimeZone.getTimeZone("UTC"));
        SpringApplication.run(DonationApplication.class, args);
    }
}

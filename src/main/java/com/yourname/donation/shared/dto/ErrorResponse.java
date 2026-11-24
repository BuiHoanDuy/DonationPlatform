package com.yourname.donation.shared.dto;

import com.fasterxml.jackson.annotation.JsonInclude;

import java.time.Instant;
import java.util.List;

/** Định dạng lỗi thống nhất của toàn bộ API (spec §10.1). */
@JsonInclude(JsonInclude.Include.NON_EMPTY)
public record ErrorResponse(
        Instant timestamp,
        int status,
        String code,
        String message,
        String path,
        String requestId,
        List<FieldErrorItem> errors) {

    public record FieldErrorItem(String field, String message) {
    }
}

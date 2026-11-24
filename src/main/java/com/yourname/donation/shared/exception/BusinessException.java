package com.yourname.donation.shared.exception;

/** Lỗi nghiệp vụ dự kiến trước; được GlobalExceptionHandler đổi thành phản hồi lỗi thống nhất. */
public class BusinessException extends RuntimeException {

    private final ErrorCode errorCode;

    public BusinessException(ErrorCode errorCode) {
        super(errorCode.defaultMessage());
        this.errorCode = errorCode;
    }

    public BusinessException(ErrorCode errorCode, String message) {
        super(message);
        this.errorCode = errorCode;
    }

    public ErrorCode getErrorCode() {
        return errorCode;
    }
}

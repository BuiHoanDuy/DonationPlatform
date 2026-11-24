-- V7: dữ liệu tham chiếu (roles, danh mục). Tài khoản Admin được tạo khi ứng dụng khởi động
-- (đọc ADMIN_EMAIL / ADMIN_PASSWORD từ biến môi trường), không nằm trong migration.
INSERT INTO roles (name, description) VALUES
    ('USER',      'Nhà hảo tâm / thành viên'),
    ('ORGANIZER', 'Người tổ chức chiến dịch'),
    ('ADMIN',     'Quản trị viên');

INSERT INTO categories (name, slug, description, icon, sort_order) VALUES
    ('Giáo dục',           'giao-duc',       'Học bổng, trường học, sách vở',          'school',    1),
    ('Y tế',               'y-te',           'Chữa bệnh, phẫu thuật, thuốc men',       'medical',   2),
    ('Trẻ em',             'tre-em',         'Trẻ mồ côi, trẻ em vùng cao',            'child',     3),
    ('Người cao tuổi',     'nguoi-cao-tuoi', 'Hỗ trợ người già neo đơn',               'elderly',   4),
    ('Thiên tai / Bão lũ', 'thien-tai',      'Cứu trợ khẩn cấp',                       'flood',     5),
    ('Môi trường',         'moi-truong',     'Trồng cây, dọn rác, bảo vệ môi trường',  'leaf',      6),
    ('Động vật',           'dong-vat',       'Cứu hộ và bảo vệ động vật',              'paw',       7),
    ('Cộng đồng',          'cong-dong',      'Hoạt động vì cộng đồng',                 'community', 8);

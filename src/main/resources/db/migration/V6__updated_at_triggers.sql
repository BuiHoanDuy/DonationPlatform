-- V6: Trigger tự cập nhật updated_at
-- =====================================================================
-- Trigger tự cập nhật updated_at
-- =====================================================================
DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'users','organizer_profiles','campaigns','campaign_updates','donations',
        'payment_transactions','expenses','volunteer_positions','volunteer_registrations','comments']
    LOOP
        EXECUTE format(
            'CREATE TRIGGER trg_%I_updated_at BEFORE UPDATE ON %I
             FOR EACH ROW EXECUTE FUNCTION set_updated_at()', t, t);
    END LOOP;
END $$;


CREATE TABLE patients (
    patient_id SERIAL PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL
);

CREATE TABLE doctors (
    doctor_id SERIAL PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL
);

CREATE TABLE appointments (
    appointment_id SERIAL PRIMARY KEY,
    patient_id INTEGER NOT NULL REFERENCES patients(patient_id),
    doctor_id INTEGER NOT NULL REFERENCES doctors(doctor_id),
    appointment_day DATE NOT NULL,
    slot_time TIME NOT NULL,
    status VARCHAR(10) NOT NULL
        CHECK (status IN ('BOOKED', 'ATTENDED', 'CANCELLED'))
);

CREATE TABLE clinic_summary (
    summary_date DATE PRIMARY KEY,
    booked_count INTEGER NOT NULL,
    attended_count INTEGER NOT NULL,
    cancelled_count INTEGER NOT NULL
);

INSERT INTO patients (full_name)
VALUES
    ('John Banda'),
    ('Mary Phiri'),
    ('Peter Zulu');

INSERT INTO doctors (full_name)
VALUES
    ('Dr. Smith'),
    ('Dr. Jones'),
    ('Dr. Brown');

INSERT INTO appointments (
    patient_id, doctor_id, appointment_day, slot_time, status
)
VALUES
    (1, 1, CURRENT_DATE, TIME '09:00', 'BOOKED'),
    (2, 1, CURRENT_DATE, TIME '10:00', 'BOOKED'),
    (3, 1, CURRENT_DATE, TIME '11:00', 'ATTENDED'),
    (1, 2, CURRENT_DATE, TIME '09:00', 'BOOKED'),
    (2, 2, CURRENT_DATE, TIME '10:00', 'CANCELLED'),
    (3, 3, CURRENT_DATE, TIME '12:00', 'BOOKED');


CREATE OR REPLACE FUNCTION fn_daily_load(
    p_doctor_id INTEGER,
    p_day DATE
)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM doctors
        WHERE doctor_id = p_doctor_id
    ) THEN
        RAISE EXCEPTION 'Unknown doctor';
    END IF;

    SELECT COUNT(*)::INTEGER
    INTO v_count
    FROM appointments
    WHERE doctor_id = p_doctor_id
    AND appointment_day = p_day
    AND status <> 'CANCELLED';

    RETURN v_count;
END;
$$;


CREATE OR REPLACE PROCEDURE pr_book_appointment(
    p_patient_id INTEGER,
    p_doctor_id INTEGER,
    p_day DATE,
    p_slot TIME
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM patients
        WHERE patient_id = p_patient_id
    ) THEN
        RAISE EXCEPTION 'Unknown patient';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM doctors
        WHERE doctor_id = p_doctor_id
    ) THEN
        RAISE EXCEPTION 'Unknown doctor';
    END IF;

    IF p_day < CURRENT_DATE THEN
        RAISE EXCEPTION 'Appointment date cannot be in the past';
    END IF;

    IF p_slot NOT IN (
        TIME '09:00',
        TIME '10:00',
        TIME '11:00',
        TIME '12:00'
    ) THEN
        RAISE EXCEPTION 'Unsupported appointment slot';
    END IF;

    INSERT INTO appointments (
        patient_id,
        doctor_id,
        appointment_day,
        slot_time,
        status
    )
    VALUES (
        p_patient_id,
        p_doctor_id,
        p_day,
        p_slot,
        'BOOKED'
    );
END;
$$;


CREATE OR REPLACE FUNCTION fn_check_appointment_clash()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.status <> 'CANCELLED'
       AND EXISTS (
            SELECT 1
            FROM appointments
            WHERE doctor_id = NEW.doctor_id
            AND appointment_day = NEW.appointment_day
            AND slot_time = NEW.slot_time
            AND status <> 'CANCELLED'
            AND appointment_id <> COALESCE(NEW.appointment_id, -1)
       )
    THEN
        RAISE EXCEPTION 'Appointment slot is already occupied';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_appointment_clash
BEFORE INSERT OR UPDATE ON appointments
FOR EACH ROW
EXECUTE FUNCTION fn_check_appointment_clash();


CREATE OR REPLACE VIEW v_today_appointments AS
SELECT
    p.full_name AS patient_name,
    d.full_name AS doctor_name,
    a.slot_time
FROM appointments a
JOIN patients p ON a.patient_id = p.patient_id
JOIN doctors d ON a.doctor_id = d.doctor_id
WHERE a.appointment_day = CURRENT_DATE
AND a.status = 'BOOKED';

SELECT * FROM v_today_appointments;


CREATE INDEX idx_appointments_day_doctor
ON appointments (appointment_day, doctor_id);

EXPLAIN
SELECT *
FROM appointments
WHERE appointment_day = CURRENT_DATE
AND doctor_id = 1;


CREATE OR REPLACE PROCEDURE pr_refresh_clinic_summary(
    p_day DATE
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO clinic_summary (
        summary_date,
        booked_count,
        attended_count,
        cancelled_count
    )
    SELECT
        p_day,
        COUNT(*) FILTER (WHERE status = 'BOOKED')::INTEGER,
        COUNT(*) FILTER (WHERE status = 'ATTENDED')::INTEGER,
        COUNT(*) FILTER (WHERE status = 'CANCELLED')::INTEGER
    FROM appointments
    WHERE appointment_day = p_day

    ON CONFLICT (summary_date)
    DO UPDATE SET
        booked_count = EXCLUDED.booked_count,
        attended_count = EXCLUDED.attended_count,
        cancelled_count = EXCLUDED.cancelled_count;
END;
$$;

CALL pr_refresh_clinic_summary(CURRENT_DATE - 1);

SELECT * FROM clinic_summary;
CALL pr_refresh_clinic_summary(CURRENT_DATE - 1);
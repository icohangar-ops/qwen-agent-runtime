-- ============================================================
-- HealthGuard AI - Patient Health Data Model
-- SurrealDB Multi-Model (Document + Graph + Relational + Time-Series)
-- ============================================================
-- Demonstrates SurrealDB's multi-model capabilities:
--   - Patient records as DOCUMENTS
--   - Doctor-Patient-Provider relationships as GRAPH
--   - Appointments/Treatments as RELATIONAL
--   - Vitals/Labs as TIME-SERIES
--   - Health records with GEO data (facilities)
-- ============================================================

USE NS healthguard;
USE DB clinical;

-- ============================================================
-- TABLES
-- ============================================================

-- Patient: primary health record (document model)
DEFINE TABLE patient SCHEMAFULL
    PERMISSIONS
        FOR select WHERE id = $auth.patient OR $auth.role IN ['doctor', 'nurse', 'admin'] OR $auth.facility = out.facility,
        FOR create WHERE $auth.role IN ['admin', 'receptionist'],
        FOR update WHERE $auth.role IN ['doctor', 'admin'],
        FOR delete WHERE $auth.role = 'admin';

DEFINE FIELD first_name ON TABLE patient TYPE string;
DEFINE FIELD last_name ON TABLE patient TYPE string;
DEFINE FIELD date_of_birth ON TABLE patient TYPE datetime;
DEFINE FIELD gender ON TABLE patient TYPE string;
DEFINE FIELD email ON TABLE patient TYPE option<string>;
DEFINE FIELD phone ON TABLE patient TYPE option<string>;
DEFINE FIELD address ON TABLE patient TYPE option<object>;
DEFINE FIELD emergency_contact ON TABLE patient TYPE option<object>;
DEFINE FIELD blood_type ON TABLE patient TYPE option<string>;
DEFINE FIELD allergies ON TABLE patient TYPE array DEFAULT [];
DEFINE FIELD insurance_id ON TABLE patient TYPE option<string>;
DEFINE FIELD facility ON TABLE patient TYPE option<record<facility>>;
DEFINE FIELD status ON TABLE patient TYPE string DEFAULT 'active';
DEFINE FIELD created_at ON TABLE patient TYPE datetime DEFAULT time::now();
DEFINE FIELD updated_at ON TABLE patient TYPE datetime DEFAULT time::now();

DEFINE INDEX idx_patient_name ON TABLE patient FIELDS first_name, last_name;
DEFINE INDEX idx_patient_facility ON TABLE patient FIELDS facility;
DEFINE INDEX idx_patient_status ON TABLE patient FIELDS status;
DEFINE INDEX ft_patient_search ON TABLE patient FIELDS first_name, last_name, allergies SEARCH ANALYZER bm25 TOKENIZERS blank,class;

-- Provider: doctors, nurses, specialists (document model)
DEFINE TABLE provider SCHEMAFULL
    PERMISSIONS
        FOR select FULL,
        FOR create WHERE $auth.role = 'admin',
        FOR update WHERE $auth.role = 'admin',
        FOR delete WHERE $auth.role = 'admin';

DEFINE FIELD first_name ON TABLE provider TYPE string;
DEFINE FIELD last_name ON TABLE provider TYPE string;
DEFINE FIELD specialty ON TABLE provider TYPE string; -- cardiology, neurology, general, etc.
DEFINE FIELD license_number ON TABLE provider TYPE string;
DEFINE FIELD email ON TABLE provider TYPE option<string>;
DEFINE FIELD phone ON TABLE provider TYPE option<string>;
DEFINE FIELD facilities ON TABLE provider TYPE array; -- list of facility record IDs
DEFINE FIELD status ON TABLE provider TYPE string DEFAULT 'active';
DEFINE FIELD created_at ON TABLE provider TYPE datetime DEFAULT time::now();

DEFINE INDEX idx_provider_name ON TABLE provider FIELDS first_name, last_name;
DEFINE INDEX idx_provider_specialty ON TABLE provider FIELDS specialty;
DEFINE INDEX ft_provider_search ON TABLE provider FIELDS first_name, last_name, specialty SEARCH ANALYZER bm25 TOKENIZERS blank,class;

-- Facility: hospitals, clinics, labs (document + geospatial)
DEFINE TABLE facility SCHEMAFULL
    PERMISSIONS
        FOR select FULL,
        FOR create WHERE $auth.role = 'admin',
        FOR update WHERE $auth.role = 'admin',
        FOR delete WHERE $auth.role = 'admin';

DEFINE FIELD name ON TABLE facility TYPE string;
DEFINE FIELD facility_type ON TABLE facility TYPE string; -- hospital, clinic, lab, pharmacy
DEFINE FIELD address ON TABLE facility TYPE object;
DEFINE FIELD coordinates ON TABLE facility TYPE geometry<point>; -- geospatial
DEFINE FIELD phone ON TABLE facility TYPE option<string>;
DEFINE FIELD capacity ON TABLE facility TYPE option<int>;
DEFINE FIELD status ON TABLE facility TYPE string DEFAULT 'active';
DEFINE FIELD created_at ON TABLE facility TYPE datetime DEFAULT time::now();

DEFINE INDEX idx_facility_type ON TABLE facility FIELDS facility_type;

-- Appointment: scheduled visits (relational model)
DEFINE TABLE appointment SCHEMAFULL
    PERMISSIONS
        FOR select WHERE in = $auth.patient OR out = $auth.provider OR $auth.role IN ['admin', 'receptionist'],
        FOR create WHERE $auth.role IN ['admin', 'receptionist', 'doctor'],
        FOR update WHERE $auth.role IN ['admin', 'doctor', 'receptionist'],
        FOR delete WHERE $auth.role = 'admin';

DEFINE FIELD appointment_date ON TABLE appointment TYPE datetime;
DEFINE FIELD appointment_type ON TABLE appointment TYPE string; -- consultation, followup, emergency, lab
DEFINE FIELD status ON TABLE appointment TYPE string DEFAULT 'scheduled'; -- scheduled, completed, cancelled, no_show
DEFINE FIELD notes ON TABLE appointment TYPE option<string>;
DEFINE FIELD duration_minutes ON TABLE appointment TYPE option<int> DEFAULT 30;
DEFINE FIELD facility ON TABLE appointment TYPE option<record<facility>>;
DEFINE FIELD created_at ON TABLE appointment TYPE datetime DEFAULT time::now();

DEFINE INDEX idx_appt_date ON TABLE appointment FIELDS appointment_date;
DEFINE INDEX idx_appt_status ON TABLE appointment FIELDS status;

-- Vital Signs: time-series health metrics
DEFINE TABLE vital_sign SCHEMAFULL
    PERMISSIONS
        FOR select WHERE $auth.role IN ['doctor', 'nurse', 'admin'],
        FOR create WHERE $auth.role IN ['doctor', 'nurse', 'device'],
        FOR update WHERE $auth.role = 'admin',
        FOR delete WHERE $auth.role = 'admin';

DEFINE FIELD patient ON TABLE vital_sign TYPE record<patient>;
DEFINE FIELD recorded_at ON TABLE vital_sign TYPE datetime DEFAULT time::now();
DEFINE FIELD heart_rate ON TABLE vital_sign TYPE option<int>; -- bpm
DEFINE FIELD blood_pressure_systolic ON TABLE vital_sign TYPE option<int>; -- mmHg
DEFINE FIELD blood_pressure_diastolic ON TABLE vital_sign TYPE option<int>; -- mmHg
DEFINE FIELD temperature ON TABLE vital_sign TYPE option<float>; -- Celsius
DEFINE FIELD oxygen_saturation ON TABLE vital_sign TYPE option<float>; -- SpO2 %
DEFINE FIELD respiratory_rate ON TABLE vital_sign TYPE option<int>; -- breaths/min
DEFINE FIELD blood_glucose ON TABLE vital_sign TYPE option<float>; -- mg/dL
DEFINE FIELD weight ON TABLE vital_sign TYPE option<float>; -- kg
DEFINE FIELD recorded_by ON TABLE vital_sign TYPE option<string>; -- provider, device, self

DEFINE INDEX idx_vital_patient ON TABLE vital_sign FIELDS patient;
DEFINE INDEX idx_vital_recorded ON TABLE vital_sign FIELDS recorded_at;

-- Lab Result: blood tests, imaging, pathology (document model)
DEFINE TABLE lab_result SCHEMAFULL
    PERMISSIONS
        FOR select WHERE patient = $auth.patient OR $auth.role IN ['doctor', 'nurse', 'admin'],
        FOR create WHERE $auth.role IN ['doctor', 'nurse', 'lab_tech'],
        FOR update WHERE $auth.role IN ['doctor', 'lab_tech', 'admin'],
        FOR delete WHERE $auth.role = 'admin';

DEFINE FIELD patient ON TABLE lab_result TYPE record<patient>;
DEFINE FIELD ordered_by ON TABLE lab_result TYPE option<record<provider>>;
DEFINE FIELD test_name ON TABLE lab_result TYPE string;
DEFINE FIELD test_category ON TABLE lab_result TYPE string; -- blood, urine, imaging, pathology
DEFINE FIELD results ON TABLE lab_result TYPE object; -- key-value pairs of test results
DEFINE FIELD reference_range ON TABLE lab_result TYPE option<object>;
DEFINE FIELD is_abnormal ON TABLE lab_result TYPE bool DEFAULT false;
DEFINE FIELD notes ON TABLE lab_result TYPE option<string>;
DEFINE FIELD collected_at ON TABLE lab_result TYPE datetime DEFAULT time::now();
DEFINE FIELD resulted_at ON TABLE lab_result TYPE option<datetime>;

DEFINE INDEX idx_lab_patient ON TABLE lab_result FIELDS patient;
DEFINE INDEX idx_lab_category ON TABLE lab_result FIELDS test_category;
DEFINE INDEX idx_lab_abnormal ON TABLE lab_result FIELDS is_abnormal;

-- AI Alert: health alerts generated by the AI engine
DEFINE TABLE ai_alert SCHEMAFULL
    PERMISSIONS
        FOR select WHERE patient = $auth.patient OR $auth.role IN ['doctor', 'admin'],
        FOR create WHERE $auth.role IN ['ai_system', 'admin'],
        FOR update WHERE $auth.role IN ['doctor', 'admin'],
        FOR delete WHERE $auth.role = 'admin';

DEFINE FIELD patient ON TABLE ai_alert TYPE record<patient>;
DEFINE FIELD alert_type ON TABLE ai_alert TYPE string; -- critical, warning, informational, trend
DEFINE FIELD category ON TABLE ai_alert TYPE string; -- cardiology, diabetes, respiratory, medication
DEFINE FIELD title ON TABLE ai_alert TYPE string;
DEFINE FIELD description ON TABLE ai_alert TYPE string;
DEFINE FIELD confidence ON TABLE ai_alert TYPE option<float>; -- 0.0 - 1.0
DEFINE FIELD model_id ON TABLE ai_alert TYPE option<string>; -- which AI model generated it
DEFINE FIELD status ON TABLE ai_alert TYPE string DEFAULT 'new'; -- new, acknowledged, dismissed, resolved
DEFINE FIELD acknowledged_by ON TABLE ai_alert TYPE option<record<provider>>;
DEFINE FIELD acknowledged_at ON TABLE ai_alert TYPE option<datetime>;
DEFINE FIELD created_at ON TABLE ai_alert TYPE datetime DEFAULT time::now();

DEFINE INDEX idx_alert_patient ON TABLE ai_alert FIELDS patient;
DEFINE INDEX idx_alert_type ON TABLE ai_alert FIELDS alert_type;
DEFINE INDEX idx_alert_status ON TABLE ai_alert FIELDS status;
DEFINE INDEX idx_alert_category ON TABLE ai_alert FIELDS category;
DEFINE INDEX idx_alert_created ON TABLE ai_alert FIELDS created_at;

-- ============================================================
-- GRAPH EDGES
-- ============================================================

-- Patient assigned to a provider (care team)
DEFINE TABLE assigned_to SCHEMAFULL TYPE RELATION IN patient OUT provider;

-- Provider works at a facility
DEFINE TABLE works_at SCHEMAFULL TYPE RELATION IN provider OUT facility;

-- ============================================================
-- EVENTS (triggers)
-- ============================================================

-- Flag abnormal lab results
DEFINE EVENT flag_abnormal_lab ON TABLE lab_result WHEN $event = 'CREATE' THEN (
    IF $after.is_abnormal THEN (
        CREATE ai_alert SET
            patient = $after.patient,
            alert_type = 'warning',
            category = 'lab',
            title = 'Abnormal lab result: ' + $after.test_name,
            description = 'One or more values outside reference range. Review results and consider follow-up.',
            model_id = 'rule-engine',
            status = 'new'
    )
);

-- ============================================================
-- SAMPLE DATA
-- ============================================================

-- Facilities
CREATE facility SET
    name = 'Metro General Hospital',
    facility_type = 'hospital',
    address = { street: '100 Health Ave', city: 'Springfield', state: 'IL', zip: '62701' },
    coordinates = geometry::point(-89.6501, 39.7817),
    capacity = 500,
    status = 'active';

CREATE facility SET
    name = 'Westside Medical Center',
    facility_type = 'clinic',
    address = { street: '250 Care Blvd', city: 'Springfield', state: 'IL', zip: '62704' },
    coordinates = geometry::point(-89.6612, 39.7983),
    capacity = 100,
    status = 'active';

-- Providers
CREATE provider SET
    first_name = 'Sarah',
    last_name = 'Chen',
    specialty = 'cardiology',
    license_number = 'MD-2024-00142',
    status = 'active';

CREATE provider SET
    first_name = 'James',
    last_name = 'Wilson',
    specialty = 'general',
    license_number = 'MD-2024-00087',
    status = 'active';

-- ============================================================
-- EXAMPLE QUERIES
-- ============================================================

-- Find all patients of a specific doctor (graph traversal)
-- SELECT in.id, in.first_name, in.last_name
-- FROM assigned_to
-- WHERE out.license_number = 'MD-2024-00142';

-- Get patient vital signs time-series (last 30 days)
-- SELECT recorded_at, heart_rate, blood_pressure_systolic,
--        blood_pressure_diastolic, temperature, oxygen_saturation
-- FROM vital_sign
-- WHERE patient = patient:abc123
-- AND recorded_at > time::now() - 30d
-- ORDER BY recorded_at ASC;

-- Find all critical AI alerts across all patients (monitoring dashboard)
-- SELECT patient.first_name, patient.last_name, title, category, confidence, created_at
-- FROM ai_alert
-- WHERE alert_type = 'critical'
-- AND status = 'new'
-- ORDER BY created_at DESC;

-- Nearby facilities within 10km radius (geospatial)
-- SELECT name, facility_type, address
-- FROM facility
-- WHERE coordinates INSIDE geometry::circle(geometry::point(-89.65, 39.78), 10000);

-- Find all abnormal lab results (cardiology related)
-- SELECT patient.first_name, patient.last_name, test_name, results, collected_at
-- FROM lab_result
-- WHERE is_abnormal = true
-- AND test_category = 'blood'
-- ORDER BY collected_at DESC;

-- Full-text search for patient records
-- SELECT * FROM patient WHERE first_name @@ 'Sarah' AND allergies CONTAINS 'penicillin';

-- AI trend analysis: patients with rising blood pressure
-- SELECT patient, recorded_at, blood_pressure_systolic
-- FROM vital_sign
-- WHERE blood_pressure_systolic > 130
-- ORDER BY patient, recorded_at ASC;

-- Real-time: live new alerts (for monitoring dashboard)
-- LIVE SELECT * FROM ai_alert WHERE status = 'new' PARALLEL;

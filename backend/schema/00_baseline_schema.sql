-- ============================================================================
-- DHOWN MES — PROPOSED baseline schema (00_baseline_schema.sql)
--
-- ⚠️  STATUS: PROPOSED — PENDING YOUR REVIEW. NOT VALIDATED. DO NOT PROVISION
--     with this until it is reviewed and explicitly approved. See
--     remediation/10_SCHEMA_RECOVERY_REPORT.md.
--
-- WHAT THIS IS
--   A SCHEMA-ONLY (data-stripped) extract of a genuine PostgreSQL pg_dump of the
--   DHOWN MES database. It is NOT hand-written or reverse-engineered DDL.
--
-- PROVENANCE (recovered, not invented)
--   Source file : backend/backups/dhown_mes_2026-07-05.sql
--   Original repo: github.com/Nakuld9/DHOWN_LIVE_PRODUCTION_DASHBOARD
--   Branch/commit: server-refractor @ 8f257f362a8854706a7a8b01ce0c2df38a3652b5
--   Dump tool   : pg_dump 18.4   DB server: PostgreSQL 18.4
--   Dump date   : 2026-07-05
--
-- SCRUBBING (verified)
--   ALL data removed: every `COPY ... FROM stdin;` block and its rows, and all
--   `\.` terminators, were stripped (verified 0 COPY / 0 INSERT / 0 data rows).
--   Only DDL remains: 63 tables, 55 sequences, 39 indexes, constraints/defaults
--   (ALTER TABLE), 1 trigger function (`update_updated_at_column`) + 1 trigger.
--   No literal credentials/secrets found in the retained DDL.
--
-- SCOPE & LIMITS (important)
--   * This is the JULY-2026 foundational schema (63 tables). Its unique value is
--     the 18 foundational tables that NO source file creates (users, machines,
--     operators, rolls, rfid_events, machine_status_log, machine_downtime,
--     machine_live_data, app_settings, audit_logs, data_collectors, fabric_types,
--     maintenance_records, oee_records, operator_assignments, production_records,
--     subcontract_challan_items, subcontract_receipt_items).
--   * It is NOT the full current schema. Post-July tables/columns are expected to
--     be layered on top by the committed legacy migrations + schema.js ensures
--     (which guard with IF NOT EXISTS / ADD COLUMN IF NOT EXISTS).
--   * UNCERTAIN (to confirm only during the approval-gated verification run):
--     - July table definitions vs current (post-July ALTERs) — reconciled by
--       ensures, not yet verified end-to-end.
--     - Possible constraint/index NAME collisions between this baseline and the
--       ensures (mostly guarded, but unverified).
--   * Do NOT treat this as complete or production-ready until two clean-DB
--     provisioning runs + the full e2e suite pass against it.
-- ============================================================================

--
-- PostgreSQL database dump
--

\restrict LKnnp2RKK98KuRpbFwjtrxF7TkMBAcvZbWggjahvEwz68t8kAK265A0A7qNoXDA

-- Dumped from database version 18.4
-- Dumped by pg_dump version 18.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_updated_at_column() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: app_settings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.app_settings (
    key character varying(100) NOT NULL,
    value text,
    updated_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.app_settings OWNER TO postgres;

--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.audit_logs (
    id integer NOT NULL,
    user_id integer,
    username character varying(50),
    action character varying(100) NOT NULL,
    module character varying(50) NOT NULL,
    old_value text,
    new_value text,
    "timestamp" timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.audit_logs OWNER TO postgres;

--
-- Name: audit_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.audit_logs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.audit_logs_id_seq OWNER TO postgres;

--
-- Name: audit_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.audit_logs_id_seq OWNED BY public.audit_logs.id;


--
-- Name: batch_rolls; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.batch_rolls (
    id integer NOT NULL,
    batch_id integer NOT NULL,
    roll_id character varying(100) NOT NULL,
    added_at timestamp without time zone DEFAULT now(),
    added_by character varying(50)
);


ALTER TABLE public.batch_rolls OWNER TO postgres;

--
-- Name: batch_rolls_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.batch_rolls_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.batch_rolls_id_seq OWNER TO postgres;

--
-- Name: batch_rolls_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.batch_rolls_id_seq OWNED BY public.batch_rolls.id;


--
-- Name: batches; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.batches (
    batch_id integer NOT NULL,
    batch_number character varying(30) NOT NULL,
    fabric_type character varying(50),
    color_code character varying(50),
    color_name character varying(100),
    total_weight_kg numeric(10,3) DEFAULT 0,
    roll_count integer DEFAULT 0,
    status character varying(20) DEFAULT 'OPEN'::character varying,
    notes text,
    created_by character varying(50),
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.batches OWNER TO postgres;

--
-- Name: batches_batch_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.batches_batch_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.batches_batch_id_seq OWNER TO postgres;

--
-- Name: batches_batch_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.batches_batch_id_seq OWNED BY public.batches.batch_id;


--
-- Name: bins; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.bins (
    bin_id integer NOT NULL,
    rack_id integer NOT NULL,
    code character varying(30) NOT NULL,
    is_active boolean DEFAULT true
);


ALTER TABLE public.bins OWNER TO postgres;

--
-- Name: bins_bin_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.bins_bin_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.bins_bin_id_seq OWNER TO postgres;

--
-- Name: bins_bin_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.bins_bin_id_seq OWNED BY public.bins.bin_id;


--
-- Name: bom_lines; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.bom_lines (
    bom_line_id integer NOT NULL,
    fabric_item_id integer NOT NULL,
    yarn_item_id integer NOT NULL,
    percentage numeric(6,2) NOT NULL,
    sort_order integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT bom_lines_percentage_check CHECK (((percentage > (0)::numeric) AND (percentage <= (100)::numeric)))
);


ALTER TABLE public.bom_lines OWNER TO postgres;

--
-- Name: bom_lines_bom_line_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.bom_lines_bom_line_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.bom_lines_bom_line_id_seq OWNER TO postgres;

--
-- Name: bom_lines_bom_line_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.bom_lines_bom_line_id_seq OWNED BY public.bom_lines.bom_line_id;


--
-- Name: cost_centres; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.cost_centres (
    cc_id integer NOT NULL,
    code character varying(20) NOT NULL,
    name character varying(100) NOT NULL,
    dept_id integer,
    is_active boolean DEFAULT true
);


ALTER TABLE public.cost_centres OWNER TO postgres;

--
-- Name: cost_centres_cc_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.cost_centres_cc_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.cost_centres_cc_id_seq OWNER TO postgres;

--
-- Name: cost_centres_cc_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.cost_centres_cc_id_seq OWNED BY public.cost_centres.cc_id;


--
-- Name: cost_entries; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.cost_entries (
    entry_id integer NOT NULL,
    reference_type character varying(30) NOT NULL,
    reference_id character varying(100) NOT NULL,
    cost_component character varying(40) NOT NULL,
    amount_rs numeric(12,2) DEFAULT 0 NOT NULL,
    quantity_kg numeric(10,3),
    rate_used numeric(10,2),
    fabric_type character varying(100),
    color_name character varying(100),
    notes text,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.cost_entries OWNER TO postgres;

--
-- Name: cost_entries_entry_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.cost_entries_entry_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.cost_entries_entry_id_seq OWNER TO postgres;

--
-- Name: cost_entries_entry_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.cost_entries_entry_id_seq OWNED BY public.cost_entries.entry_id;


--
-- Name: cost_rates; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.cost_rates (
    rate_id integer NOT NULL,
    yarn_type character varying(100) NOT NULL,
    price_per_kg numeric(10,2) DEFAULT 0 NOT NULL,
    labour_per_shift numeric(10,2) DEFAULT 0 NOT NULL,
    machine_depreciation_per_hour numeric(10,2) DEFAULT 0 NOT NULL,
    notes text,
    updated_by character varying(80),
    updated_at timestamp without time zone DEFAULT now(),
    item_id integer
);


ALTER TABLE public.cost_rates OWNER TO postgres;

--
-- Name: cost_rates_rate_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.cost_rates_rate_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.cost_rates_rate_id_seq OWNER TO postgres;

--
-- Name: cost_rates_rate_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.cost_rates_rate_id_seq OWNED BY public.cost_rates.rate_id;


--
-- Name: cost_snapshots; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.cost_snapshots (
    snapshot_id integer NOT NULL,
    snapshot_date date NOT NULL,
    fabric_type character varying(100),
    color_name character varying(100),
    total_cost_rs numeric(12,2) DEFAULT 0,
    total_kg numeric(10,3) DEFAULT 0,
    cost_per_kg numeric(10,2) DEFAULT 0,
    selling_price_kg numeric(10,2),
    margin_rs numeric(12,2),
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.cost_snapshots OWNER TO postgres;

--
-- Name: cost_snapshots_snapshot_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.cost_snapshots_snapshot_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.cost_snapshots_snapshot_id_seq OWNER TO postgres;

--
-- Name: cost_snapshots_snapshot_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.cost_snapshots_snapshot_id_seq OWNED BY public.cost_snapshots.snapshot_id;


--
-- Name: data_collectors; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.data_collectors (
    dc_id character varying(50) NOT NULL,
    machine_id character varying(20),
    ip_address character varying(50),
    status character varying(20),
    last_seen timestamp without time zone
);


ALTER TABLE public.data_collectors OWNER TO postgres;

--
-- Name: departments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.departments (
    dept_id integer NOT NULL,
    code character varying(20) NOT NULL,
    name character varying(100) NOT NULL,
    head_user character varying(80),
    is_active boolean DEFAULT true
);


ALTER TABLE public.departments OWNER TO postgres;

--
-- Name: departments_dept_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.departments_dept_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.departments_dept_id_seq OWNER TO postgres;

--
-- Name: departments_dept_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.departments_dept_id_seq OWNED BY public.departments.dept_id;


--
-- Name: dispatch_challans; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.dispatch_challans (
    dispatch_id integer NOT NULL,
    dispatch_number character varying(30) NOT NULL,
    customer_name character varying(100) NOT NULL,
    customer_contact character varying(50),
    dispatch_date date NOT NULL,
    total_weight_kg numeric(10,3) DEFAULT 0,
    status character varying(20) DEFAULT 'DISPATCHED'::character varying,
    notes text,
    created_by character varying(50),
    created_at timestamp without time zone DEFAULT now(),
    vehicle_number character varying(50),
    partner_id integer,
    dispatch_type character varying(20) DEFAULT 'FG'::character varying,
    total_taxable_value numeric(12,2),
    total_gst numeric(12,2),
    grand_total numeric(12,2)
);


ALTER TABLE public.dispatch_challans OWNER TO postgres;

--
-- Name: dispatch_challans_dispatch_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.dispatch_challans_dispatch_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.dispatch_challans_dispatch_id_seq OWNER TO postgres;

--
-- Name: dispatch_challans_dispatch_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.dispatch_challans_dispatch_id_seq OWNED BY public.dispatch_challans.dispatch_id;


--
-- Name: dispatch_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.dispatch_items (
    item_id integer NOT NULL,
    dispatch_id integer NOT NULL,
    fg_id integer,
    weight_kg numeric(10,3),
    fabric_type character varying(50),
    color_name character varying(100),
    item_type character varying(20) DEFAULT 'FG'::character varying,
    roll_id integer,
    lot_id integer,
    item_description character varying(300),
    lot_number character varying(100),
    yarn_type character varying(100),
    color character varying(100),
    rate_per_kg numeric(10,2),
    gst_rate numeric(5,2),
    taxable_value numeric(12,2),
    gst_amount numeric(12,2),
    line_total numeric(12,2)
);


ALTER TABLE public.dispatch_items OWNER TO postgres;

--
-- Name: dispatch_items_item_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.dispatch_items_item_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.dispatch_items_item_id_seq OWNER TO postgres;

--
-- Name: dispatch_items_item_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.dispatch_items_item_id_seq OWNED BY public.dispatch_items.item_id;


--
-- Name: doc_series; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.doc_series (
    series_id integer NOT NULL,
    series_code character varying(20) NOT NULL,
    prefix character varying(20) NOT NULL,
    suffix character varying(20) DEFAULT ''::character varying,
    include_year boolean DEFAULT true,
    include_month boolean DEFAULT false,
    zero_pad integer DEFAULT 4,
    current_seq integer DEFAULT 0,
    fin_year character varying(9),
    reset_yearly boolean DEFAULT true,
    last_reset date,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.doc_series OWNER TO postgres;

--
-- Name: doc_series_series_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.doc_series_series_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.doc_series_series_id_seq OWNER TO postgres;

--
-- Name: doc_series_series_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.doc_series_series_id_seq OWNED BY public.doc_series.series_id;


--
-- Name: fabric_types; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fabric_types (
    code character varying(10) NOT NULL,
    name character varying(100) NOT NULL,
    description character varying(255),
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.fabric_types OWNER TO postgres;

--
-- Name: financial_years; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.financial_years (
    fy_id integer NOT NULL,
    label character varying(9) NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    is_active boolean DEFAULT false,
    is_closed boolean DEFAULT false
);


ALTER TABLE public.financial_years OWNER TO postgres;

--
-- Name: financial_years_fy_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.financial_years_fy_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.financial_years_fy_id_seq OWNER TO postgres;

--
-- Name: financial_years_fy_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.financial_years_fy_id_seq OWNED BY public.financial_years.fy_id;


--
-- Name: finished_goods; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.finished_goods (
    fg_id integer NOT NULL,
    receipt_id integer,
    batch_id integer,
    fabric_type character varying(50),
    color_code character varying(50),
    color_name character varying(100),
    weight_kg numeric(10,3),
    roll_count integer DEFAULT 0,
    status character varying(20) DEFAULT 'IN_STOCK'::character varying,
    location character varying(100),
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    source character varying(20) DEFAULT 'REGULAR'::character varying,
    lot_no character varying(80)
);


ALTER TABLE public.finished_goods OWNER TO postgres;

--
-- Name: finished_goods_fg_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.finished_goods_fg_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.finished_goods_fg_id_seq OWNER TO postgres;

--
-- Name: finished_goods_fg_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.finished_goods_fg_id_seq OWNED BY public.finished_goods.fg_id;


--
-- Name: finishing_records; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.finishing_records (
    finishing_id integer NOT NULL,
    receipt_id integer,
    batch_id integer,
    shade character varying(80),
    gsm numeric(8,2),
    moisture_pct numeric(5,2),
    shrinkage_pct numeric(5,2),
    damage_kg numeric(10,3) DEFAULT 0,
    qa_passed boolean DEFAULT true,
    qa_notes text,
    finished_by character varying(80),
    finished_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.finishing_records OWNER TO postgres;

--
-- Name: finishing_records_finishing_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.finishing_records_finishing_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.finishing_records_finishing_id_seq OWNER TO postgres;

--
-- Name: finishing_records_finishing_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.finishing_records_finishing_id_seq OWNED BY public.finishing_records.finishing_id;


--
-- Name: grn; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.grn (
    grn_id integer NOT NULL,
    grn_number character varying(40) NOT NULL,
    supplier_name character varying(150) NOT NULL,
    supplier_invoice character varying(100),
    receipt_date date DEFAULT CURRENT_DATE NOT NULL,
    vehicle_number character varying(50),
    received_by character varying(80),
    status character varying(20) DEFAULT 'DRAFT'::character varying,
    notes text,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    partner_id integer,
    warehouse_id integer
);


ALTER TABLE public.grn OWNER TO postgres;

--
-- Name: grn_grn_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.grn_grn_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.grn_grn_id_seq OWNER TO postgres;

--
-- Name: grn_grn_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.grn_grn_id_seq OWNED BY public.grn.grn_id;


--
-- Name: hsn_codes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.hsn_codes (
    hsn_id integer NOT NULL,
    hsn_code character varying(20) NOT NULL,
    description text,
    gst_rate numeric(5,2) DEFAULT 0
);


ALTER TABLE public.hsn_codes OWNER TO postgres;

--
-- Name: hsn_codes_hsn_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.hsn_codes_hsn_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.hsn_codes_hsn_id_seq OWNER TO postgres;

--
-- Name: hsn_codes_hsn_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.hsn_codes_hsn_id_seq OWNED BY public.hsn_codes.hsn_id;


--
-- Name: item_categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.item_categories (
    category_id integer NOT NULL,
    code character varying(30) NOT NULL,
    name character varying(100) NOT NULL,
    description text,
    parent_id integer,
    is_active boolean DEFAULT true
);


ALTER TABLE public.item_categories OWNER TO postgres;

--
-- Name: item_categories_category_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.item_categories_category_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.item_categories_category_id_seq OWNER TO postgres;

--
-- Name: item_categories_category_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.item_categories_category_id_seq OWNED BY public.item_categories.category_id;


--
-- Name: item_fabric_attrs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.item_fabric_attrs (
    item_id integer NOT NULL,
    fabric_code character varying(50),
    structure character varying(100),
    gsm numeric(8,2),
    finished_gsm numeric(8,2),
    width_cm numeric(6,2),
    finished_width_cm numeric(6,2),
    machine_type character varying(50),
    gauge character varying(20),
    dia_inches numeric(6,2),
    feeders integer,
    stitch_length_mm numeric(6,3),
    process_route_id integer
);


ALTER TABLE public.item_fabric_attrs OWNER TO postgres;

--
-- Name: item_spare_attrs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.item_spare_attrs (
    item_id integer NOT NULL,
    oem_part_number character varying(100),
    compatible_machine character varying(200),
    rack_bin character varying(50),
    warranty_months integer,
    default_partner_id integer
);


ALTER TABLE public.item_spare_attrs OWNER TO postgres;

--
-- Name: item_yarn_attrs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.item_yarn_attrs (
    item_id integer NOT NULL,
    count character varying(30),
    composition character varying(100),
    shade character varying(80),
    yarn_type character varying(80),
    default_partner_id integer,
    pref_warehouse_id integer,
    pref_rack_id integer
);


ALTER TABLE public.item_yarn_attrs OWNER TO postgres;

--
-- Name: items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.items (
    item_id integer NOT NULL,
    item_code character varying(50) NOT NULL,
    item_name character varying(200) NOT NULL,
    category_id integer NOT NULL,
    description text,
    uom_id integer,
    hsn_id integer,
    gst_rate numeric(5,2) DEFAULT 0,
    standard_cost numeric(15,2) DEFAULT 0,
    status character varying(20) DEFAULT 'ACTIVE'::character varying,
    is_active boolean DEFAULT true,
    created_by character varying(80),
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    knitting_rate_per_kg numeric(10,2),
    standard_loss_pct numeric(5,2) DEFAULT 1.00
);


ALTER TABLE public.items OWNER TO postgres;

--
-- Name: items_item_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.items_item_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.items_item_id_seq OWNER TO postgres;

--
-- Name: items_item_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.items_item_id_seq OWNED BY public.items.item_id;


--
-- Name: machine_downtime; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.machine_downtime (
    id integer NOT NULL,
    machine_id character varying(20),
    reason character varying(200),
    start_time timestamp without time zone,
    end_time timestamp without time zone,
    duration_minutes numeric(10,2),
    status character varying(20) DEFAULT 'OPEN'::character varying,
    source character varying(20) DEFAULT 'MANUAL'::character varying,
    shift character varying(2)
);


ALTER TABLE public.machine_downtime OWNER TO postgres;

--
-- Name: machine_downtime_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.machine_downtime_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.machine_downtime_id_seq OWNER TO postgres;

--
-- Name: machine_downtime_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.machine_downtime_id_seq OWNED BY public.machine_downtime.id;


--
-- Name: machine_live_data; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.machine_live_data (
    id integer NOT NULL,
    machine_id character varying(20),
    rpm integer,
    status character varying(20),
    production_counter numeric(10,2),
    operator_name character varying(100),
    shift character(1),
    "timestamp" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    dc_status character varying(20),
    operator_id character varying(50),
    previous_counter numeric DEFAULT 0 NOT NULL,
    session_production_kg numeric DEFAULT 0 NOT NULL,
    last_status character varying(20)
);


ALTER TABLE public.machine_live_data OWNER TO postgres;

--
-- Name: machine_live_data_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.machine_live_data_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.machine_live_data_id_seq OWNER TO postgres;

--
-- Name: machine_live_data_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.machine_live_data_id_seq OWNED BY public.machine_live_data.id;


--
-- Name: machine_status_log; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.machine_status_log (
    id integer NOT NULL,
    machine_id character varying(20) NOT NULL,
    status character varying(20) NOT NULL,
    shift character varying(2) DEFAULT 'D'::character varying NOT NULL,
    start_time timestamp without time zone DEFAULT now() NOT NULL,
    end_time timestamp without time zone,
    duration_minutes numeric
);


ALTER TABLE public.machine_status_log OWNER TO postgres;

--
-- Name: machine_status_log_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.machine_status_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.machine_status_log_id_seq OWNER TO postgres;

--
-- Name: machine_status_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.machine_status_log_id_seq OWNED BY public.machine_status_log.id;


--
-- Name: machines; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.machines (
    machine_id character varying(20) NOT NULL,
    machine_name character varying(100),
    machine_type character varying(20),
    diameter integer,
    gauge integer,
    feeders integer,
    active boolean DEFAULT true,
    fabric character varying(100),
    dc_id character varying(50),
    rpm_target integer,
    machine_status character varying(20),
    kg_per_counter numeric(12,8),
    dc_status character varying(20),
    fabric_code character varying(10),
    manufacturer character varying(100),
    model character varying(100),
    serial_number character varying(100),
    needles_count integer,
    cylinder_diameter numeric(6,2),
    purchase_date date,
    installation_date date
);


ALTER TABLE public.machines OWNER TO postgres;

--
-- Name: maintenance_records; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.maintenance_records (
    id integer NOT NULL,
    machine_id character varying(20),
    maintenance_type character varying(100),
    technician character varying(100),
    remarks text,
    maintenance_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    next_service_date timestamp without time zone,
    status character varying(50) DEFAULT 'DONE'::character varying
);


ALTER TABLE public.maintenance_records OWNER TO postgres;

--
-- Name: maintenance_records_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.maintenance_records_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.maintenance_records_id_seq OWNER TO postgres;

--
-- Name: maintenance_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.maintenance_records_id_seq OWNED BY public.maintenance_records.id;


--
-- Name: maintenance_schedule; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.maintenance_schedule (
    schedule_id integer NOT NULL,
    machine_id character varying(20) NOT NULL,
    task_name character varying(200) NOT NULL,
    task_type character varying(50) DEFAULT 'PERIODIC'::character varying NOT NULL,
    frequency_days integer,
    frequency_hours integer,
    last_done_date date,
    last_done_hours numeric(10,2),
    next_due_date date,
    next_due_hours numeric(10,2),
    assigned_to character varying(100),
    priority character varying(20) DEFAULT 'MEDIUM'::character varying,
    notes text,
    status character varying(20) DEFAULT 'ACTIVE'::character varying,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT maintenance_schedule_priority_check CHECK (((priority)::text = ANY ((ARRAY['LOW'::character varying, 'MEDIUM'::character varying, 'HIGH'::character varying, 'CRITICAL'::character varying])::text[]))),
    CONSTRAINT maintenance_schedule_status_check CHECK (((status)::text = ANY ((ARRAY['ACTIVE'::character varying, 'PAUSED'::character varying, 'COMPLETED'::character varying])::text[])))
);


ALTER TABLE public.maintenance_schedule OWNER TO postgres;

--
-- Name: maintenance_schedule_schedule_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.maintenance_schedule_schedule_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.maintenance_schedule_schedule_id_seq OWNER TO postgres;

--
-- Name: maintenance_schedule_schedule_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.maintenance_schedule_schedule_id_seq OWNED BY public.maintenance_schedule.schedule_id;


--
-- Name: oee_records; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.oee_records (
    id integer NOT NULL,
    machine_id character varying(20) NOT NULL,
    record_date date NOT NULL,
    shift character varying(2) NOT NULL,
    planned_minutes numeric DEFAULT 480 NOT NULL,
    run_minutes numeric DEFAULT 0 NOT NULL,
    stopped_minutes numeric DEFAULT 0 NOT NULL,
    availability numeric DEFAULT 0 NOT NULL,
    performance numeric DEFAULT 0 NOT NULL,
    quality numeric DEFAULT 100 NOT NULL,
    oee numeric DEFAULT 0 NOT NULL,
    production_kg numeric DEFAULT 0 NOT NULL,
    rpm_avg numeric DEFAULT 0 NOT NULL,
    sample_count integer DEFAULT 0 NOT NULL,
    updated_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.oee_records OWNER TO postgres;

--
-- Name: oee_records_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.oee_records_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.oee_records_id_seq OWNER TO postgres;

--
-- Name: oee_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.oee_records_id_seq OWNED BY public.oee_records.id;


--
-- Name: operator_assignments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.operator_assignments (
    assignment_id integer NOT NULL,
    operator_id integer,
    machine_id character varying(20),
    assigned_at timestamp without time zone DEFAULT now(),
    released_at timestamp without time zone,
    status character varying(20) DEFAULT 'ACTIVE'::character varying,
    operator_name character varying(100)
);


ALTER TABLE public.operator_assignments OWNER TO postgres;

--
-- Name: operator_assignments_assignment_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.operator_assignments_assignment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.operator_assignments_assignment_id_seq OWNER TO postgres;

--
-- Name: operator_assignments_assignment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.operator_assignments_assignment_id_seq OWNED BY public.operator_assignments.assignment_id;


--
-- Name: operator_attendance; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.operator_attendance (
    attendance_id integer NOT NULL,
    operator_id character varying(50) NOT NULL,
    operator_name character varying(100),
    work_date date NOT NULL,
    shift character(1),
    clock_in timestamp without time zone,
    clock_out timestamp without time zone,
    last_seen timestamp without time zone,
    scan_count integer DEFAULT 1,
    status character varying(20) DEFAULT 'PRESENT'::character varying,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.operator_attendance OWNER TO postgres;

--
-- Name: operator_attendance_attendance_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.operator_attendance_attendance_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.operator_attendance_attendance_id_seq OWNER TO postgres;

--
-- Name: operator_attendance_attendance_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.operator_attendance_attendance_id_seq OWNED BY public.operator_attendance.attendance_id;


--
-- Name: operators; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.operators (
    operator_id integer NOT NULL,
    operator_code character varying(20),
    operator_name character varying(100),
    rfid_tag character varying(50),
    mobile character varying(20),
    status character varying(20) DEFAULT 'ACTIVE'::character varying,
    created_at timestamp without time zone DEFAULT now(),
    department character varying(50),
    shift character varying(10),
    updated_at timestamp without time zone DEFAULT now(),
    employee_id character varying(50),
    join_date date,
    skill_level character varying(20) DEFAULT 'BASIC'::character varying,
    emergency_contact character varying(20),
    CONSTRAINT operators_skill_level_check CHECK (((skill_level)::text = ANY ((ARRAY['BASIC'::character varying, 'INTERMEDIATE'::character varying, 'EXPERT'::character varying])::text[])))
);


ALTER TABLE public.operators OWNER TO postgres;

--
-- Name: operators_operator_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.operators_operator_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.operators_operator_id_seq OWNER TO postgres;

--
-- Name: operators_operator_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.operators_operator_id_seq OWNED BY public.operators.operator_id;


--
-- Name: partner_addresses; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.partner_addresses (
    address_id integer NOT NULL,
    partner_id integer NOT NULL,
    address_type character varying(30) DEFAULT 'PRIMARY'::character varying,
    line1 character varying(200),
    line2 character varying(200),
    city character varying(100),
    state character varying(100),
    pincode character varying(10),
    country character varying(50) DEFAULT 'India'::character varying,
    gstin character varying(20),
    is_default boolean DEFAULT false
);


ALTER TABLE public.partner_addresses OWNER TO postgres;

--
-- Name: partner_addresses_address_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.partner_addresses_address_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.partner_addresses_address_id_seq OWNER TO postgres;

--
-- Name: partner_addresses_address_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.partner_addresses_address_id_seq OWNED BY public.partner_addresses.address_id;


--
-- Name: partner_bank; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.partner_bank (
    bank_id integer NOT NULL,
    partner_id integer NOT NULL,
    bank_name character varying(100),
    branch character varying(100),
    account_no character varying(50),
    ifsc character varying(20),
    account_type character varying(30) DEFAULT 'CURRENT'::character varying,
    is_default boolean DEFAULT false
);


ALTER TABLE public.partner_bank OWNER TO postgres;

--
-- Name: partner_bank_bank_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.partner_bank_bank_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.partner_bank_bank_id_seq OWNER TO postgres;

--
-- Name: partner_bank_bank_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.partner_bank_bank_id_seq OWNED BY public.partner_bank.bank_id;


--
-- Name: partner_contacts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.partner_contacts (
    contact_id integer NOT NULL,
    partner_id integer NOT NULL,
    name character varying(100) NOT NULL,
    designation character varying(100),
    mobile character varying(20),
    email character varying(100),
    whatsapp character varying(20),
    is_primary boolean DEFAULT false
);


ALTER TABLE public.partner_contacts OWNER TO postgres;

--
-- Name: partner_contacts_contact_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.partner_contacts_contact_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.partner_contacts_contact_id_seq OWNER TO postgres;

--
-- Name: partner_contacts_contact_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.partner_contacts_contact_id_seq OWNED BY public.partner_contacts.contact_id;


--
-- Name: partner_roles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.partner_roles (
    role_id integer NOT NULL,
    partner_id integer NOT NULL,
    role character varying(50) NOT NULL,
    is_primary boolean DEFAULT false
);


ALTER TABLE public.partner_roles OWNER TO postgres;

--
-- Name: partner_roles_role_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.partner_roles_role_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.partner_roles_role_id_seq OWNER TO postgres;

--
-- Name: partner_roles_role_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.partner_roles_role_id_seq OWNED BY public.partner_roles.role_id;


--
-- Name: partners; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.partners (
    partner_id integer NOT NULL,
    partner_code character varying(30) NOT NULL,
    company_name character varying(200) NOT NULL,
    short_name character varying(80),
    gstin character varying(20),
    pan character varying(20),
    tan character varying(20),
    iec character varying(20),
    cin character varying(30),
    msme_number character varying(50),
    msme_category character varying(10),
    payment_terms integer DEFAULT 30,
    credit_limit numeric(15,2),
    credit_days integer DEFAULT 0,
    rating integer,
    notes text,
    is_active boolean DEFAULT true,
    created_by character varying(80),
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    CONSTRAINT partners_rating_check CHECK (((rating >= 1) AND (rating <= 5)))
);


ALTER TABLE public.partners OWNER TO postgres;

--
-- Name: partners_partner_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.partners_partner_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.partners_partner_id_seq OWNER TO postgres;

--
-- Name: partners_partner_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.partners_partner_id_seq OWNED BY public.partners.partner_id;


--
-- Name: process_route_steps; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.process_route_steps (
    step_id integer NOT NULL,
    route_id integer NOT NULL,
    step_order integer NOT NULL,
    step_code character varying(30) NOT NULL,
    step_name character varying(100) NOT NULL,
    location_type character varying(30) DEFAULT 'INTERNAL'::character varying,
    dept_id integer,
    generates_document character varying(50),
    is_optional boolean DEFAULT false
);


ALTER TABLE public.process_route_steps OWNER TO postgres;

--
-- Name: process_route_steps_step_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.process_route_steps_step_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.process_route_steps_step_id_seq OWNER TO postgres;

--
-- Name: process_route_steps_step_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.process_route_steps_step_id_seq OWNED BY public.process_route_steps.step_id;


--
-- Name: process_routes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.process_routes (
    route_id integer NOT NULL,
    code character varying(30) NOT NULL,
    name character varying(100) NOT NULL,
    description text,
    item_category character varying(50),
    is_active boolean DEFAULT true,
    created_by character varying(80),
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.process_routes OWNER TO postgres;

--
-- Name: process_routes_route_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.process_routes_route_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.process_routes_route_id_seq OWNER TO postgres;

--
-- Name: process_routes_route_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.process_routes_route_id_seq OWNED BY public.process_routes.route_id;


--
-- Name: production_history; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.production_history (
    id bigint NOT NULL,
    machine_id character varying(20) NOT NULL,
    period_type character varying(10) NOT NULL,
    period_start timestamp with time zone NOT NULL,
    period_end timestamp with time zone NOT NULL,
    shift character varying(2) DEFAULT ''::character varying NOT NULL,
    record_date date NOT NULL,
    hour_bucket smallint DEFAULT '-1'::integer NOT NULL,
    counter_start numeric(12,0) DEFAULT 0 NOT NULL,
    counter_end numeric(12,0) DEFAULT 0 NOT NULL,
    production_kg numeric(10,4) DEFAULT 0 NOT NULL,
    rpm_avg numeric(6,2) DEFAULT 0 NOT NULL,
    sample_count integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT chk_period_type CHECK (((period_type)::text = ANY ((ARRAY['HOURLY'::character varying, 'SHIFT'::character varying, 'DAILY'::character varying])::text[])))
);


ALTER TABLE public.production_history OWNER TO postgres;

--
-- Name: production_history_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.production_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.production_history_id_seq OWNER TO postgres;

--
-- Name: production_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.production_history_id_seq OWNED BY public.production_history.id;


--
-- Name: production_records; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.production_records (
    id integer NOT NULL,
    machine_id character varying(20) NOT NULL,
    record_date date NOT NULL,
    shift character varying(2) NOT NULL,
    counter_start bigint DEFAULT 0 NOT NULL,
    counter_end bigint DEFAULT 0 NOT NULL,
    production_kg numeric DEFAULT 0 NOT NULL,
    rpm_sum numeric DEFAULT 0 NOT NULL,
    sample_count integer DEFAULT 0 NOT NULL,
    updated_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.production_records OWNER TO postgres;

--
-- Name: production_records_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.production_records_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.production_records_id_seq OWNER TO postgres;

--
-- Name: production_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.production_records_id_seq OWNED BY public.production_records.id;


--
-- Name: racks; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.racks (
    rack_id integer NOT NULL,
    warehouse_id integer NOT NULL,
    code character varying(30) NOT NULL,
    name character varying(100),
    is_active boolean DEFAULT true
);


ALTER TABLE public.racks OWNER TO postgres;

--
-- Name: racks_rack_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.racks_rack_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.racks_rack_id_seq OWNER TO postgres;

--
-- Name: racks_rack_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.racks_rack_id_seq OWNED BY public.racks.rack_id;


--
-- Name: rfid_events; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.rfid_events (
    event_id integer NOT NULL,
    rfid_tag character varying(50),
    operator_id integer,
    machine_id character varying(20),
    event_time timestamp without time zone DEFAULT now()
);


ALTER TABLE public.rfid_events OWNER TO postgres;

--
-- Name: rfid_events_event_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.rfid_events_event_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.rfid_events_event_id_seq OWNER TO postgres;

--
-- Name: rfid_events_event_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.rfid_events_event_id_seq OWNED BY public.rfid_events.event_id;


--
-- Name: rolls; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.rolls (
    roll_id character varying(50) NOT NULL,
    machine_id character varying(20),
    fabric_type character varying(100),
    weight_kg numeric(10,2),
    shift character(1),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    start_counter bigint,
    current_counter bigint,
    roll_weight_kg numeric(10,2),
    status character varying(20),
    operator_id character varying(50),
    supervisor_id character varying(50),
    actual_weight_kg numeric(10,2),
    verified_at timestamp without time zone,
    closed_at timestamp without time zone,
    supervisor_name character varying(100),
    approved_at timestamp without time zone,
    warehouse_status character varying(30) DEFAULT 'GREIGE'::character varying,
    lot_id integer,
    issue_id integer,
    qr_image text,
    fabric_item_id integer,
    source character varying(20) DEFAULT 'REGULAR'::character varying
);


ALTER TABLE public.rolls OWNER TO postgres;

--
-- Name: sc_challan_yarn_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sc_challan_yarn_items (
    item_id integer NOT NULL,
    challan_id integer NOT NULL,
    lot_id integer,
    lot_number character varying(50),
    yarn_type character varying(100),
    color character varying(100),
    sent_kg numeric(10,3) NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.sc_challan_yarn_items OWNER TO postgres;

--
-- Name: sc_challan_yarn_items_item_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.sc_challan_yarn_items_item_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.sc_challan_yarn_items_item_id_seq OWNER TO postgres;

--
-- Name: sc_challan_yarn_items_item_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.sc_challan_yarn_items_item_id_seq OWNED BY public.sc_challan_yarn_items.item_id;


--
-- Name: shift_handovers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.shift_handovers (
    handover_id integer NOT NULL,
    shift_date date NOT NULL,
    shift character varying(5) NOT NULL,
    supervisor_name character varying(100),
    production_kg numeric(10,2),
    machines_down integer DEFAULT 0,
    issues text,
    actions_taken text,
    pending_actions text,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.shift_handovers OWNER TO postgres;

--
-- Name: shift_handovers_handover_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.shift_handovers_handover_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.shift_handovers_handover_id_seq OWNER TO postgres;

--
-- Name: shift_handovers_handover_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.shift_handovers_handover_id_seq OWNED BY public.shift_handovers.handover_id;


--
-- Name: stock_ledger; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.stock_ledger (
    ledger_id bigint NOT NULL,
    txn_date date DEFAULT CURRENT_DATE NOT NULL,
    txn_time timestamp without time zone DEFAULT now(),
    doc_type character varying(30) NOT NULL,
    doc_id character varying(100) NOT NULL,
    item_id integer,
    item_desc character varying(200),
    warehouse_id integer,
    rack_id integer,
    bin_id integer,
    movement_type character varying(20) NOT NULL,
    quantity numeric(12,3) NOT NULL,
    uom_code character varying(20) DEFAULT 'KG'::character varying,
    unit_cost numeric(15,2),
    total_cost numeric(15,2),
    partner_id integer,
    notes text,
    created_by character varying(80),
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.stock_ledger OWNER TO postgres;

--
-- Name: stock_ledger_ledger_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.stock_ledger_ledger_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.stock_ledger_ledger_id_seq OWNER TO postgres;

--
-- Name: stock_ledger_ledger_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.stock_ledger_ledger_id_seq OWNED BY public.stock_ledger.ledger_id;


--
-- Name: subcontract_challan_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.subcontract_challan_items (
    item_id integer NOT NULL,
    challan_id integer,
    batch_id integer,
    fabric_type character varying(100),
    color character varying(100),
    roll_count integer DEFAULT 0,
    weight_kg numeric(10,3) DEFAULT 0,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.subcontract_challan_items OWNER TO postgres;

--
-- Name: subcontract_challan_items_item_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.subcontract_challan_items_item_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.subcontract_challan_items_item_id_seq OWNER TO postgres;

--
-- Name: subcontract_challan_items_item_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.subcontract_challan_items_item_id_seq OWNED BY public.subcontract_challan_items.item_id;


--
-- Name: subcontract_challans; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.subcontract_challans (
    challan_id integer NOT NULL,
    challan_number character varying(30) NOT NULL,
    batch_id integer,
    vendor_name character varying(100),
    vendor_contact character varying(50),
    job_type character varying(30) NOT NULL,
    sent_date date NOT NULL,
    expected_return_date date,
    sent_weight_kg numeric(10,3),
    roll_count integer DEFAULT 0,
    rate_per_kg numeric(10,2),
    status character varying(20) DEFAULT 'SENT'::character varying,
    notes text,
    created_by character varying(50),
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    partner_id integer,
    challan_type character varying(20) DEFAULT 'ROLL_BASED'::character varying,
    is_job_work boolean DEFAULT false,
    customer_name character varying(200),
    source character varying(20) DEFAULT 'REGULAR'::character varying,
    forwarded_from_challan_id integer,
    color_name character varying(200)
);


ALTER TABLE public.subcontract_challans OWNER TO postgres;

--
-- Name: subcontract_challans_challan_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.subcontract_challans_challan_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.subcontract_challans_challan_id_seq OWNER TO postgres;

--
-- Name: subcontract_challans_challan_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.subcontract_challans_challan_id_seq OWNED BY public.subcontract_challans.challan_id;


--
-- Name: subcontract_receipt_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.subcontract_receipt_items (
    item_id integer NOT NULL,
    receipt_id integer,
    fabric_type character varying(100),
    batch_id integer,
    color character varying(100),
    weight_kg numeric(10,3) DEFAULT 0,
    new_roll_id character varying(50),
    created_at timestamp without time zone DEFAULT now(),
    depth character varying(20),
    roll_count integer DEFAULT 0,
    rate_per_kg numeric(10,2),
    amount numeric(12,2),
    process character varying(100)
);


ALTER TABLE public.subcontract_receipt_items OWNER TO postgres;

--
-- Name: subcontract_receipt_items_item_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.subcontract_receipt_items_item_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.subcontract_receipt_items_item_id_seq OWNER TO postgres;

--
-- Name: subcontract_receipt_items_item_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.subcontract_receipt_items_item_id_seq OWNED BY public.subcontract_receipt_items.item_id;


--
-- Name: subcontract_receipts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.subcontract_receipts (
    receipt_id integer NOT NULL,
    challan_id integer NOT NULL,
    received_date date NOT NULL,
    received_weight_kg numeric(10,3),
    quality_status character varying(20) DEFAULT 'PASS'::character varying,
    rejected_weight_kg numeric(10,3) DEFAULT 0,
    notes text,
    received_by character varying(50),
    created_at timestamp without time zone DEFAULT now(),
    shade character varying(80),
    gsm numeric(8,2),
    rolls_received_count integer DEFAULT 0,
    balance_yarn_kg numeric(10,3) DEFAULT 0,
    vendor_invoice_no character varying(100),
    vendor_bill_amount numeric(12,2),
    payment_status character varying(20) DEFAULT 'PENDING'::character varying
);


ALTER TABLE public.subcontract_receipts OWNER TO postgres;

--
-- Name: subcontract_receipts_receipt_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.subcontract_receipts_receipt_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.subcontract_receipts_receipt_id_seq OWNER TO postgres;

--
-- Name: subcontract_receipts_receipt_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.subcontract_receipts_receipt_id_seq OWNED BY public.subcontract_receipts.receipt_id;


--
-- Name: tax_rates; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tax_rates (
    tax_id integer NOT NULL,
    code character varying(20) NOT NULL,
    name character varying(50) NOT NULL,
    cgst numeric(5,2) DEFAULT 0,
    sgst numeric(5,2) DEFAULT 0,
    igst numeric(5,2) DEFAULT 0,
    is_active boolean DEFAULT true
);


ALTER TABLE public.tax_rates OWNER TO postgres;

--
-- Name: tax_rates_tax_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.tax_rates_tax_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tax_rates_tax_id_seq OWNER TO postgres;

--
-- Name: tax_rates_tax_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.tax_rates_tax_id_seq OWNED BY public.tax_rates.tax_id;


--
-- Name: uom; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.uom (
    uom_id integer NOT NULL,
    code character varying(20) NOT NULL,
    name character varying(50) NOT NULL,
    is_active boolean DEFAULT true
);


ALTER TABLE public.uom OWNER TO postgres;

--
-- Name: uom_uom_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.uom_uom_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.uom_uom_id_seq OWNER TO postgres;

--
-- Name: uom_uom_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.uom_uom_id_seq OWNED BY public.uom.uom_id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    id integer NOT NULL,
    username character varying(50) NOT NULL,
    full_name character varying(100) NOT NULL,
    password_hash character varying(255) NOT NULL,
    role character varying(30) DEFAULT 'VIEWER'::character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    mobile character varying(20),
    pin_hash character varying(100)
);


ALTER TABLE public.users OWNER TO postgres;

--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.users_id_seq OWNER TO postgres;

--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: warehouses; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.warehouses (
    warehouse_id integer NOT NULL,
    code character varying(20) NOT NULL,
    name character varying(100) NOT NULL,
    type character varying(30) DEFAULT 'INTERNAL'::character varying,
    address text,
    is_active boolean DEFAULT true
);


ALTER TABLE public.warehouses OWNER TO postgres;

--
-- Name: warehouses_warehouse_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.warehouses_warehouse_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.warehouses_warehouse_id_seq OWNER TO postgres;

--
-- Name: warehouses_warehouse_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.warehouses_warehouse_id_seq OWNED BY public.warehouses.warehouse_id;


--
-- Name: yarn_issue_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.yarn_issue_items (
    item_id integer NOT NULL,
    issue_id integer NOT NULL,
    lot_id integer NOT NULL,
    issued_kg numeric(10,3) NOT NULL,
    returned_kg numeric(10,3) DEFAULT 0,
    consumed_kg numeric(10,3) GENERATED ALWAYS AS ((issued_kg - returned_kg)) STORED,
    issued_cones integer DEFAULT 0
);


ALTER TABLE public.yarn_issue_items OWNER TO postgres;

--
-- Name: yarn_issue_items_item_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.yarn_issue_items_item_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.yarn_issue_items_item_id_seq OWNER TO postgres;

--
-- Name: yarn_issue_items_item_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.yarn_issue_items_item_id_seq OWNED BY public.yarn_issue_items.item_id;


--
-- Name: yarn_issues; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.yarn_issues (
    issue_id integer NOT NULL,
    issue_number character varying(40) NOT NULL,
    issue_date date DEFAULT CURRENT_DATE NOT NULL,
    machine_id character varying(20),
    machine_name character varying(100),
    issued_by character varying(80),
    received_by character varying(80),
    status character varying(20) DEFAULT 'ISSUED'::character varying,
    notes text,
    created_at timestamp without time zone DEFAULT now(),
    cost_centre_id integer,
    source character varying(20) DEFAULT 'REGULAR'::character varying
);


ALTER TABLE public.yarn_issues OWNER TO postgres;

--
-- Name: yarn_issues_issue_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.yarn_issues_issue_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.yarn_issues_issue_id_seq OWNER TO postgres;

--
-- Name: yarn_issues_issue_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.yarn_issues_issue_id_seq OWNED BY public.yarn_issues.issue_id;


--
-- Name: yarn_lot_movements; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.yarn_lot_movements (
    movement_id integer NOT NULL,
    lot_id integer NOT NULL,
    movement_type character varying(30) NOT NULL,
    quantity_kg numeric(10,3) NOT NULL,
    before_kg numeric(10,3),
    after_kg numeric(10,3),
    reference_id integer,
    reference_type character varying(30),
    notes text,
    created_by character varying(80),
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.yarn_lot_movements OWNER TO postgres;

--
-- Name: yarn_lot_movements_movement_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.yarn_lot_movements_movement_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.yarn_lot_movements_movement_id_seq OWNER TO postgres;

--
-- Name: yarn_lot_movements_movement_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.yarn_lot_movements_movement_id_seq OWNED BY public.yarn_lot_movements.movement_id;


--
-- Name: yarn_lots; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.yarn_lots (
    lot_id integer NOT NULL,
    lot_number character varying(40) NOT NULL,
    grn_id integer,
    yarn_type character varying(100) NOT NULL,
    count character varying(30),
    color character varying(80) DEFAULT 'Grey'::character varying,
    supplier_lot_no character varying(80),
    net_weight_kg numeric(10,3) NOT NULL,
    cones integer DEFAULT 0,
    rate_per_kg numeric(10,2),
    current_stock_kg numeric(10,3) DEFAULT 0,
    status character varying(20) DEFAULT 'IN_STORE'::character varying,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    item_id integer,
    low_stock_threshold_kg numeric(10,3),
    source character varying(20) DEFAULT 'REGULAR'::character varying,
    brand character varying(100),
    location character varying(50),
    current_cones integer DEFAULT 0
);


ALTER TABLE public.yarn_lots OWNER TO postgres;

--
-- Name: yarn_lots_lot_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.yarn_lots_lot_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.yarn_lots_lot_id_seq OWNER TO postgres;

--
-- Name: yarn_lots_lot_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.yarn_lots_lot_id_seq OWNED BY public.yarn_lots.lot_id;


--
-- Name: audit_logs id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audit_logs ALTER COLUMN id SET DEFAULT nextval('public.audit_logs_id_seq'::regclass);


--
-- Name: batch_rolls id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.batch_rolls ALTER COLUMN id SET DEFAULT nextval('public.batch_rolls_id_seq'::regclass);


--
-- Name: batches batch_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.batches ALTER COLUMN batch_id SET DEFAULT nextval('public.batches_batch_id_seq'::regclass);


--
-- Name: bins bin_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bins ALTER COLUMN bin_id SET DEFAULT nextval('public.bins_bin_id_seq'::regclass);


--
-- Name: bom_lines bom_line_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bom_lines ALTER COLUMN bom_line_id SET DEFAULT nextval('public.bom_lines_bom_line_id_seq'::regclass);


--
-- Name: cost_centres cc_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cost_centres ALTER COLUMN cc_id SET DEFAULT nextval('public.cost_centres_cc_id_seq'::regclass);


--
-- Name: cost_entries entry_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cost_entries ALTER COLUMN entry_id SET DEFAULT nextval('public.cost_entries_entry_id_seq'::regclass);


--
-- Name: cost_rates rate_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cost_rates ALTER COLUMN rate_id SET DEFAULT nextval('public.cost_rates_rate_id_seq'::regclass);


--
-- Name: cost_snapshots snapshot_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cost_snapshots ALTER COLUMN snapshot_id SET DEFAULT nextval('public.cost_snapshots_snapshot_id_seq'::regclass);


--
-- Name: departments dept_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.departments ALTER COLUMN dept_id SET DEFAULT nextval('public.departments_dept_id_seq'::regclass);


--
-- Name: dispatch_challans dispatch_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dispatch_challans ALTER COLUMN dispatch_id SET DEFAULT nextval('public.dispatch_challans_dispatch_id_seq'::regclass);


--
-- Name: dispatch_items item_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dispatch_items ALTER COLUMN item_id SET DEFAULT nextval('public.dispatch_items_item_id_seq'::regclass);


--
-- Name: doc_series series_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.doc_series ALTER COLUMN series_id SET DEFAULT nextval('public.doc_series_series_id_seq'::regclass);


--
-- Name: financial_years fy_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.financial_years ALTER COLUMN fy_id SET DEFAULT nextval('public.financial_years_fy_id_seq'::regclass);


--
-- Name: finished_goods fg_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.finished_goods ALTER COLUMN fg_id SET DEFAULT nextval('public.finished_goods_fg_id_seq'::regclass);


--
-- Name: finishing_records finishing_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.finishing_records ALTER COLUMN finishing_id SET DEFAULT nextval('public.finishing_records_finishing_id_seq'::regclass);


--
-- Name: grn grn_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.grn ALTER COLUMN grn_id SET DEFAULT nextval('public.grn_grn_id_seq'::regclass);


--
-- Name: hsn_codes hsn_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.hsn_codes ALTER COLUMN hsn_id SET DEFAULT nextval('public.hsn_codes_hsn_id_seq'::regclass);


--
-- Name: item_categories category_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.item_categories ALTER COLUMN category_id SET DEFAULT nextval('public.item_categories_category_id_seq'::regclass);


--
-- Name: items item_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.items ALTER COLUMN item_id SET DEFAULT nextval('public.items_item_id_seq'::regclass);


--
-- Name: machine_downtime id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.machine_downtime ALTER COLUMN id SET DEFAULT nextval('public.machine_downtime_id_seq'::regclass);


--
-- Name: machine_live_data id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.machine_live_data ALTER COLUMN id SET DEFAULT nextval('public.machine_live_data_id_seq'::regclass);


--
-- Name: machine_status_log id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.machine_status_log ALTER COLUMN id SET DEFAULT nextval('public.machine_status_log_id_seq'::regclass);


--
-- Name: maintenance_records id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.maintenance_records ALTER COLUMN id SET DEFAULT nextval('public.maintenance_records_id_seq'::regclass);


--
-- Name: maintenance_schedule schedule_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.maintenance_schedule ALTER COLUMN schedule_id SET DEFAULT nextval('public.maintenance_schedule_schedule_id_seq'::regclass);


--
-- Name: oee_records id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.oee_records ALTER COLUMN id SET DEFAULT nextval('public.oee_records_id_seq'::regclass);


--
-- Name: operator_assignments assignment_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.operator_assignments ALTER COLUMN assignment_id SET DEFAULT nextval('public.operator_assignments_assignment_id_seq'::regclass);


--
-- Name: operator_attendance attendance_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.operator_attendance ALTER COLUMN attendance_id SET DEFAULT nextval('public.operator_attendance_attendance_id_seq'::regclass);


--
-- Name: operators operator_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.operators ALTER COLUMN operator_id SET DEFAULT nextval('public.operators_operator_id_seq'::regclass);


--
-- Name: partner_addresses address_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.partner_addresses ALTER COLUMN address_id SET DEFAULT nextval('public.partner_addresses_address_id_seq'::regclass);


--
-- Name: partner_bank bank_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.partner_bank ALTER COLUMN bank_id SET DEFAULT nextval('public.partner_bank_bank_id_seq'::regclass);


--
-- Name: partner_contacts contact_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.partner_contacts ALTER COLUMN contact_id SET DEFAULT nextval('public.partner_contacts_contact_id_seq'::regclass);


--
-- Name: partner_roles role_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.partner_roles ALTER COLUMN role_id SET DEFAULT nextval('public.partner_roles_role_id_seq'::regclass);


--
-- Name: partners partner_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.partners ALTER COLUMN partner_id SET DEFAULT nextval('public.partners_partner_id_seq'::regclass);


--
-- Name: process_route_steps step_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.process_route_steps ALTER COLUMN step_id SET DEFAULT nextval('public.process_route_steps_step_id_seq'::regclass);


--
-- Name: process_routes route_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.process_routes ALTER COLUMN route_id SET DEFAULT nextval('public.process_routes_route_id_seq'::regclass);


--
-- Name: production_history id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.production_history ALTER COLUMN id SET DEFAULT nextval('public.production_history_id_seq'::regclass);


--
-- Name: production_records id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.production_records ALTER COLUMN id SET DEFAULT nextval('public.production_records_id_seq'::regclass);


--
-- Name: racks rack_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.racks ALTER COLUMN rack_id SET DEFAULT nextval('public.racks_rack_id_seq'::regclass);


--
-- Name: rfid_events event_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rfid_events ALTER COLUMN event_id SET DEFAULT nextval('public.rfid_events_event_id_seq'::regclass);


--
-- Name: sc_challan_yarn_items item_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sc_challan_yarn_items ALTER COLUMN item_id SET DEFAULT nextval('public.sc_challan_yarn_items_item_id_seq'::regclass);


--
-- Name: shift_handovers handover_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.shift_handovers ALTER COLUMN handover_id SET DEFAULT nextval('public.shift_handovers_handover_id_seq'::regclass);


--
-- Name: stock_ledger ledger_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_ledger ALTER COLUMN ledger_id SET DEFAULT nextval('public.stock_ledger_ledger_id_seq'::regclass);


--
-- Name: subcontract_challan_items item_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subcontract_challan_items ALTER COLUMN item_id SET DEFAULT nextval('public.subcontract_challan_items_item_id_seq'::regclass);


--
-- Name: subcontract_challans challan_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subcontract_challans ALTER COLUMN challan_id SET DEFAULT nextval('public.subcontract_challans_challan_id_seq'::regclass);


--
-- Name: subcontract_receipt_items item_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subcontract_receipt_items ALTER COLUMN item_id SET DEFAULT nextval('public.subcontract_receipt_items_item_id_seq'::regclass);


--
-- Name: subcontract_receipts receipt_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subcontract_receipts ALTER COLUMN receipt_id SET DEFAULT nextval('public.subcontract_receipts_receipt_id_seq'::regclass);


--
-- Name: tax_rates tax_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tax_rates ALTER COLUMN tax_id SET DEFAULT nextval('public.tax_rates_tax_id_seq'::regclass);


--
-- Name: uom uom_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.uom ALTER COLUMN uom_id SET DEFAULT nextval('public.uom_uom_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: warehouses warehouse_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.warehouses ALTER COLUMN warehouse_id SET DEFAULT nextval('public.warehouses_warehouse_id_seq'::regclass);


--
-- Name: yarn_issue_items item_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.yarn_issue_items ALTER COLUMN item_id SET DEFAULT nextval('public.yarn_issue_items_item_id_seq'::regclass);


--
-- Name: yarn_issues issue_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.yarn_issues ALTER COLUMN issue_id SET DEFAULT nextval('public.yarn_issues_issue_id_seq'::regclass);


--
-- Name: yarn_lot_movements movement_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.yarn_lot_movements ALTER COLUMN movement_id SET DEFAULT nextval('public.yarn_lot_movements_movement_id_seq'::regclass);


--
-- Name: yarn_lots lot_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.yarn_lots ALTER COLUMN lot_id SET DEFAULT nextval('public.yarn_lots_lot_id_seq'::regclass);


--
-- Data for Name: app_settings; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: audit_logs; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: batch_rolls; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: batches; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: bins; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: bom_lines; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: cost_centres; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: cost_entries; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: cost_rates; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: cost_snapshots; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: data_collectors; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: departments; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: dispatch_challans; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: dispatch_items; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: doc_series; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: fabric_types; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: financial_years; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: finished_goods; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: finishing_records; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: grn; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: hsn_codes; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: item_categories; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: item_fabric_attrs; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: item_spare_attrs; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: item_yarn_attrs; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: items; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: machine_downtime; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: machine_live_data; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: machine_status_log; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: machines; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: maintenance_records; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: maintenance_schedule; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: oee_records; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: operator_assignments; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: operator_attendance; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: operators; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: partner_addresses; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: partner_bank; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: partner_contacts; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: partner_roles; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: partners; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: process_route_steps; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: process_routes; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: production_history; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: production_records; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: racks; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: rfid_events; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: rolls; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: sc_challan_yarn_items; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: shift_handovers; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: stock_ledger; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: subcontract_challan_items; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: subcontract_challans; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: subcontract_receipt_items; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: subcontract_receipts; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: tax_rates; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: uom; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: warehouses; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: yarn_issue_items; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: yarn_issues; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: yarn_lot_movements; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Data for Name: yarn_lots; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- Name: audit_logs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.audit_logs_id_seq', 99, true);


--
-- Name: batch_rolls_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.batch_rolls_id_seq', 12, true);


--
-- Name: batches_batch_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.batches_batch_id_seq', 3, true);


--
-- Name: bins_bin_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.bins_bin_id_seq', 36, true);


--
-- Name: bom_lines_bom_line_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.bom_lines_bom_line_id_seq', 22, true);


--
-- Name: cost_centres_cc_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.cost_centres_cc_id_seq', 5, true);


--
-- Name: cost_entries_entry_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.cost_entries_entry_id_seq', 9, true);


--
-- Name: cost_rates_rate_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.cost_rates_rate_id_seq', 7, true);


--
-- Name: cost_snapshots_snapshot_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.cost_snapshots_snapshot_id_seq', 1, false);


--
-- Name: departments_dept_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.departments_dept_id_seq', 7, true);


--
-- Name: dispatch_challans_dispatch_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.dispatch_challans_dispatch_id_seq', 1, false);


--
-- Name: dispatch_items_item_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.dispatch_items_item_id_seq', 1, false);


--
-- Name: doc_series_series_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.doc_series_series_id_seq', 10, true);


--
-- Name: financial_years_fy_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.financial_years_fy_id_seq', 2, true);


--
-- Name: finished_goods_fg_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.finished_goods_fg_id_seq', 1, false);


--
-- Name: finishing_records_finishing_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.finishing_records_finishing_id_seq', 1, false);


--
-- Name: grn_grn_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.grn_grn_id_seq', 3, true);


--
-- Name: hsn_codes_hsn_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.hsn_codes_hsn_id_seq', 12, true);


--
-- Name: item_categories_category_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.item_categories_category_id_seq', 9, true);


--
-- Name: items_item_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.items_item_id_seq', 24, true);


--
-- Name: machine_downtime_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.machine_downtime_id_seq', 17, true);


--
-- Name: machine_live_data_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.machine_live_data_id_seq', 12, true);


--
-- Name: machine_status_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.machine_status_log_id_seq', 1, true);


--
-- Name: maintenance_records_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.maintenance_records_id_seq', 2, true);


--
-- Name: maintenance_schedule_schedule_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.maintenance_schedule_schedule_id_seq', 1, false);


--
-- Name: oee_records_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.oee_records_id_seq', 3, true);


--
-- Name: operator_assignments_assignment_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.operator_assignments_assignment_id_seq', 14, true);


--
-- Name: operator_attendance_attendance_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.operator_attendance_attendance_id_seq', 1, false);


--
-- Name: operators_operator_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.operators_operator_id_seq', 16, true);


--
-- Name: partner_addresses_address_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.partner_addresses_address_id_seq', 4, true);


--
-- Name: partner_bank_bank_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.partner_bank_bank_id_seq', 3, true);


--
-- Name: partner_contacts_contact_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.partner_contacts_contact_id_seq', 6, true);


--
-- Name: partner_roles_role_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.partner_roles_role_id_seq', 9, true);


--
-- Name: partners_partner_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.partners_partner_id_seq', 7, true);


--
-- Name: process_route_steps_step_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.process_route_steps_step_id_seq', 27, true);


--
-- Name: process_routes_route_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.process_routes_route_id_seq', 5, true);


--
-- Name: production_history_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.production_history_id_seq', 2, true);


--
-- Name: production_records_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.production_records_id_seq', 8, true);


--
-- Name: racks_rack_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.racks_rack_id_seq', 11, true);


--
-- Name: rfid_events_event_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.rfid_events_event_id_seq', 2, true);


--
-- Name: sc_challan_yarn_items_item_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.sc_challan_yarn_items_item_id_seq', 1, false);


--
-- Name: shift_handovers_handover_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.shift_handovers_handover_id_seq', 1, false);


--
-- Name: stock_ledger_ledger_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.stock_ledger_ledger_id_seq', 13, true);


--
-- Name: subcontract_challan_items_item_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.subcontract_challan_items_item_id_seq', 4, true);


--
-- Name: subcontract_challans_challan_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.subcontract_challans_challan_id_seq', 3, true);


--
-- Name: subcontract_receipt_items_item_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.subcontract_receipt_items_item_id_seq', 2, true);


--
-- Name: subcontract_receipts_receipt_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.subcontract_receipts_receipt_id_seq', 1, true);


--
-- Name: tax_rates_tax_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.tax_rates_tax_id_seq', 5, true);


--
-- Name: uom_uom_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.uom_uom_id_seq', 7, true);


--
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.users_id_seq', 8, true);


--
-- Name: warehouses_warehouse_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.warehouses_warehouse_id_seq', 6, true);


--
-- Name: yarn_issue_items_item_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.yarn_issue_items_item_id_seq', 7, true);


--
-- Name: yarn_issues_issue_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.yarn_issues_issue_id_seq', 7, true);


--
-- Name: yarn_lot_movements_movement_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.yarn_lot_movements_movement_id_seq', 11, true);


--
-- Name: yarn_lots_lot_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.yarn_lots_lot_id_seq', 1, true);


--
-- Name: app_settings app_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.app_settings
    ADD CONSTRAINT app_settings_pkey PRIMARY KEY (key);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: batch_rolls batch_rolls_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.batch_rolls
    ADD CONSTRAINT batch_rolls_pkey PRIMARY KEY (id);


--
-- Name: batch_rolls batch_rolls_roll_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.batch_rolls
    ADD CONSTRAINT batch_rolls_roll_id_key UNIQUE (roll_id);


--
-- Name: batches batches_batch_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.batches
    ADD CONSTRAINT batches_batch_number_key UNIQUE (batch_number);


--
-- Name: batches batches_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.batches
    ADD CONSTRAINT batches_pkey PRIMARY KEY (batch_id);


--
-- Name: bins bins_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bins
    ADD CONSTRAINT bins_pkey PRIMARY KEY (bin_id);


--
-- Name: bins bins_rack_id_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bins
    ADD CONSTRAINT bins_rack_id_code_key UNIQUE (rack_id, code);


--
-- Name: bom_lines bom_lines_fabric_item_id_yarn_item_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bom_lines
    ADD CONSTRAINT bom_lines_fabric_item_id_yarn_item_id_key UNIQUE (fabric_item_id, yarn_item_id);


--
-- Name: bom_lines bom_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bom_lines
    ADD CONSTRAINT bom_lines_pkey PRIMARY KEY (bom_line_id);


--
-- Name: cost_centres cost_centres_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cost_centres
    ADD CONSTRAINT cost_centres_code_key UNIQUE (code);


--
-- Name: cost_centres cost_centres_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cost_centres
    ADD CONSTRAINT cost_centres_pkey PRIMARY KEY (cc_id);


--
-- Name: cost_entries cost_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cost_entries
    ADD CONSTRAINT cost_entries_pkey PRIMARY KEY (entry_id);


--
-- Name: cost_rates cost_rates_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cost_rates
    ADD CONSTRAINT cost_rates_pkey PRIMARY KEY (rate_id);


--
-- Name: cost_rates cost_rates_yarn_type_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cost_rates
    ADD CONSTRAINT cost_rates_yarn_type_key UNIQUE (yarn_type);


--
-- Name: cost_snapshots cost_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cost_snapshots
    ADD CONSTRAINT cost_snapshots_pkey PRIMARY KEY (snapshot_id);


--
-- Name: cost_snapshots cost_snapshots_snapshot_date_fabric_type_color_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cost_snapshots
    ADD CONSTRAINT cost_snapshots_snapshot_date_fabric_type_color_name_key UNIQUE (snapshot_date, fabric_type, color_name);


--
-- Name: data_collectors data_collectors_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.data_collectors
    ADD CONSTRAINT data_collectors_pkey PRIMARY KEY (dc_id);


--
-- Name: departments departments_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_code_key UNIQUE (code);


--
-- Name: departments departments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_pkey PRIMARY KEY (dept_id);


--
-- Name: dispatch_challans dispatch_challans_dispatch_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dispatch_challans
    ADD CONSTRAINT dispatch_challans_dispatch_number_key UNIQUE (dispatch_number);


--
-- Name: dispatch_challans dispatch_challans_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dispatch_challans
    ADD CONSTRAINT dispatch_challans_pkey PRIMARY KEY (dispatch_id);


--
-- Name: dispatch_items dispatch_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dispatch_items
    ADD CONSTRAINT dispatch_items_pkey PRIMARY KEY (item_id);


--
-- Name: doc_series doc_series_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.doc_series
    ADD CONSTRAINT doc_series_pkey PRIMARY KEY (series_id);


--
-- Name: doc_series doc_series_series_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.doc_series
    ADD CONSTRAINT doc_series_series_code_key UNIQUE (series_code);


--
-- Name: fabric_types fabric_types_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fabric_types
    ADD CONSTRAINT fabric_types_pkey PRIMARY KEY (code);


--
-- Name: financial_years financial_years_label_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.financial_years
    ADD CONSTRAINT financial_years_label_key UNIQUE (label);


--
-- Name: financial_years financial_years_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.financial_years
    ADD CONSTRAINT financial_years_pkey PRIMARY KEY (fy_id);


--
-- Name: finished_goods finished_goods_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.finished_goods
    ADD CONSTRAINT finished_goods_pkey PRIMARY KEY (fg_id);


--
-- Name: finishing_records finishing_records_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.finishing_records
    ADD CONSTRAINT finishing_records_pkey PRIMARY KEY (finishing_id);


--
-- Name: grn grn_grn_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.grn
    ADD CONSTRAINT grn_grn_number_key UNIQUE (grn_number);


--
-- Name: grn grn_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.grn
    ADD CONSTRAINT grn_pkey PRIMARY KEY (grn_id);


--
-- Name: hsn_codes hsn_codes_hsn_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.hsn_codes
    ADD CONSTRAINT hsn_codes_hsn_code_key UNIQUE (hsn_code);


--
-- Name: hsn_codes hsn_codes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.hsn_codes
    ADD CONSTRAINT hsn_codes_pkey PRIMARY KEY (hsn_id);


--
-- Name: item_categories item_categories_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.item_categories
    ADD CONSTRAINT item_categories_code_key UNIQUE (code);


--
-- Name: item_categories item_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.item_categories
    ADD CONSTRAINT item_categories_pkey PRIMARY KEY (category_id);


--
-- Name: item_fabric_attrs item_fabric_attrs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.item_fabric_attrs
    ADD CONSTRAINT item_fabric_attrs_pkey PRIMARY KEY (item_id);


--
-- Name: item_spare_attrs item_spare_attrs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.item_spare_attrs
    ADD CONSTRAINT item_spare_attrs_pkey PRIMARY KEY (item_id);


--
-- Name: item_yarn_attrs item_yarn_attrs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.item_yarn_attrs
    ADD CONSTRAINT item_yarn_attrs_pkey PRIMARY KEY (item_id);


--
-- Name: items items_item_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.items
    ADD CONSTRAINT items_item_code_key UNIQUE (item_code);


--
-- Name: items items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.items
    ADD CONSTRAINT items_pkey PRIMARY KEY (item_id);


--
-- Name: machine_downtime machine_downtime_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.machine_downtime
    ADD CONSTRAINT machine_downtime_pkey PRIMARY KEY (id);


--
-- Name: machine_live_data machine_live_data_machine_id_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.machine_live_data
    ADD CONSTRAINT machine_live_data_machine_id_unique UNIQUE (machine_id);


--
-- Name: machine_live_data machine_live_data_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.machine_live_data
    ADD CONSTRAINT machine_live_data_pkey PRIMARY KEY (id);


--
-- Name: machine_status_log machine_status_log_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.machine_status_log
    ADD CONSTRAINT machine_status_log_pkey PRIMARY KEY (id);


--
-- Name: machines machines_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.machines
    ADD CONSTRAINT machines_pkey PRIMARY KEY (machine_id);


--
-- Name: maintenance_records maintenance_records_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.maintenance_records
    ADD CONSTRAINT maintenance_records_pkey PRIMARY KEY (id);


--
-- Name: maintenance_schedule maintenance_schedule_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.maintenance_schedule
    ADD CONSTRAINT maintenance_schedule_pkey PRIMARY KEY (schedule_id);


--
-- Name: oee_records oee_records_machine_id_record_date_shift_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.oee_records
    ADD CONSTRAINT oee_records_machine_id_record_date_shift_key UNIQUE (machine_id, record_date, shift);


--
-- Name: oee_records oee_records_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.oee_records
    ADD CONSTRAINT oee_records_pkey PRIMARY KEY (id);


--
-- Name: operator_assignments operator_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.operator_assignments
    ADD CONSTRAINT operator_assignments_pkey PRIMARY KEY (assignment_id);


--
-- Name: operator_attendance operator_attendance_operator_id_work_date_shift_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.operator_attendance
    ADD CONSTRAINT operator_attendance_operator_id_work_date_shift_key UNIQUE (operator_id, work_date, shift);


--
-- Name: operator_attendance operator_attendance_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.operator_attendance
    ADD CONSTRAINT operator_attendance_pkey PRIMARY KEY (attendance_id);


--
-- Name: operators operators_operator_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.operators
    ADD CONSTRAINT operators_operator_code_key UNIQUE (operator_code);


--
-- Name: operators operators_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.operators
    ADD CONSTRAINT operators_pkey PRIMARY KEY (operator_id);


--
-- Name: partner_addresses partner_addresses_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.partner_addresses
    ADD CONSTRAINT partner_addresses_pkey PRIMARY KEY (address_id);


--
-- Name: partner_bank partner_bank_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.partner_bank
    ADD CONSTRAINT partner_bank_pkey PRIMARY KEY (bank_id);


--
-- Name: partner_contacts partner_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.partner_contacts
    ADD CONSTRAINT partner_contacts_pkey PRIMARY KEY (contact_id);


--
-- Name: partner_roles partner_roles_partner_id_role_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.partner_roles
    ADD CONSTRAINT partner_roles_partner_id_role_key UNIQUE (partner_id, role);


--
-- Name: partner_roles partner_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.partner_roles
    ADD CONSTRAINT partner_roles_pkey PRIMARY KEY (role_id);


--
-- Name: partners partners_partner_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.partners
    ADD CONSTRAINT partners_partner_code_key UNIQUE (partner_code);


--
-- Name: partners partners_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.partners
    ADD CONSTRAINT partners_pkey PRIMARY KEY (partner_id);


--
-- Name: process_route_steps process_route_steps_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.process_route_steps
    ADD CONSTRAINT process_route_steps_pkey PRIMARY KEY (step_id);


--
-- Name: process_route_steps process_route_steps_route_id_step_order_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.process_route_steps
    ADD CONSTRAINT process_route_steps_route_id_step_order_key UNIQUE (route_id, step_order);


--
-- Name: process_routes process_routes_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.process_routes
    ADD CONSTRAINT process_routes_code_key UNIQUE (code);


--
-- Name: process_routes process_routes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.process_routes
    ADD CONSTRAINT process_routes_pkey PRIMARY KEY (route_id);


--
-- Name: production_history production_history_machine_id_period_type_record_date_hour__key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.production_history
    ADD CONSTRAINT production_history_machine_id_period_type_record_date_hour__key UNIQUE (machine_id, period_type, record_date, hour_bucket, shift);


--
-- Name: production_history production_history_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.production_history
    ADD CONSTRAINT production_history_pkey PRIMARY KEY (id);


--
-- Name: production_records production_records_machine_id_record_date_shift_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.production_records
    ADD CONSTRAINT production_records_machine_id_record_date_shift_key UNIQUE (machine_id, record_date, shift);


--
-- Name: production_records production_records_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.production_records
    ADD CONSTRAINT production_records_pkey PRIMARY KEY (id);


--
-- Name: racks racks_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.racks
    ADD CONSTRAINT racks_pkey PRIMARY KEY (rack_id);


--
-- Name: racks racks_warehouse_id_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.racks
    ADD CONSTRAINT racks_warehouse_id_code_key UNIQUE (warehouse_id, code);


--
-- Name: rfid_events rfid_events_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rfid_events
    ADD CONSTRAINT rfid_events_pkey PRIMARY KEY (event_id);


--
-- Name: rolls rolls_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rolls
    ADD CONSTRAINT rolls_pkey PRIMARY KEY (roll_id);


--
-- Name: sc_challan_yarn_items sc_challan_yarn_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sc_challan_yarn_items
    ADD CONSTRAINT sc_challan_yarn_items_pkey PRIMARY KEY (item_id);


--
-- Name: shift_handovers shift_handovers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.shift_handovers
    ADD CONSTRAINT shift_handovers_pkey PRIMARY KEY (handover_id);


--
-- Name: stock_ledger stock_ledger_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_ledger
    ADD CONSTRAINT stock_ledger_pkey PRIMARY KEY (ledger_id);


--
-- Name: subcontract_challan_items subcontract_challan_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subcontract_challan_items
    ADD CONSTRAINT subcontract_challan_items_pkey PRIMARY KEY (item_id);


--
-- Name: subcontract_challans subcontract_challans_challan_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subcontract_challans
    ADD CONSTRAINT subcontract_challans_challan_number_key UNIQUE (challan_number);


--
-- Name: subcontract_challans subcontract_challans_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subcontract_challans
    ADD CONSTRAINT subcontract_challans_pkey PRIMARY KEY (challan_id);


--
-- Name: subcontract_receipt_items subcontract_receipt_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subcontract_receipt_items
    ADD CONSTRAINT subcontract_receipt_items_pkey PRIMARY KEY (item_id);


--
-- Name: subcontract_receipts subcontract_receipts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subcontract_receipts
    ADD CONSTRAINT subcontract_receipts_pkey PRIMARY KEY (receipt_id);


--
-- Name: tax_rates tax_rates_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tax_rates
    ADD CONSTRAINT tax_rates_code_key UNIQUE (code);


--
-- Name: tax_rates tax_rates_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tax_rates
    ADD CONSTRAINT tax_rates_pkey PRIMARY KEY (tax_id);


--
-- Name: uom uom_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.uom
    ADD CONSTRAINT uom_code_key UNIQUE (code);


--
-- Name: uom uom_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.uom
    ADD CONSTRAINT uom_pkey PRIMARY KEY (uom_id);


--
-- Name: operators uq_operators_code; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.operators
    ADD CONSTRAINT uq_operators_code UNIQUE (operator_code);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: users users_username_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_username_key UNIQUE (username);


--
-- Name: warehouses warehouses_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.warehouses
    ADD CONSTRAINT warehouses_code_key UNIQUE (code);


--
-- Name: warehouses warehouses_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.warehouses
    ADD CONSTRAINT warehouses_pkey PRIMARY KEY (warehouse_id);


--
-- Name: yarn_issue_items yarn_issue_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.yarn_issue_items
    ADD CONSTRAINT yarn_issue_items_pkey PRIMARY KEY (item_id);


--
-- Name: yarn_issues yarn_issues_issue_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.yarn_issues
    ADD CONSTRAINT yarn_issues_issue_number_key UNIQUE (issue_number);


--
-- Name: yarn_issues yarn_issues_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.yarn_issues
    ADD CONSTRAINT yarn_issues_pkey PRIMARY KEY (issue_id);


--
-- Name: yarn_lot_movements yarn_lot_movements_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.yarn_lot_movements
    ADD CONSTRAINT yarn_lot_movements_pkey PRIMARY KEY (movement_id);


--
-- Name: yarn_lots yarn_lots_lot_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.yarn_lots
    ADD CONSTRAINT yarn_lots_lot_number_key UNIQUE (lot_number);


--
-- Name: yarn_lots yarn_lots_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.yarn_lots
    ADD CONSTRAINT yarn_lots_pkey PRIMARY KEY (lot_id);


--
-- Name: idx_attendance_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_attendance_date ON public.operator_attendance USING btree (work_date, shift);


--
-- Name: idx_attendance_operator; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_attendance_operator ON public.operator_attendance USING btree (operator_id, work_date);


--
-- Name: idx_batch_rolls_batch; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_batch_rolls_batch ON public.batch_rolls USING btree (batch_id);


--
-- Name: idx_bom_fabric; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_bom_fabric ON public.bom_lines USING btree (fabric_item_id);


--
-- Name: idx_challans_batch; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_challans_batch ON public.subcontract_challans USING btree (batch_id);


--
-- Name: idx_challans_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_challans_status ON public.subcontract_challans USING btree (status);


--
-- Name: idx_cost_entries_component; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_cost_entries_component ON public.cost_entries USING btree (cost_component);


--
-- Name: idx_cost_entries_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_cost_entries_date ON public.cost_entries USING btree (created_at);


--
-- Name: idx_cost_entries_fabric; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_cost_entries_fabric ON public.cost_entries USING btree (fabric_type);


--
-- Name: idx_cost_entries_ref; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_cost_entries_ref ON public.cost_entries USING btree (reference_type, reference_id);


--
-- Name: idx_cost_snapshots_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_cost_snapshots_date ON public.cost_snapshots USING btree (snapshot_date);


--
-- Name: idx_dispatch_items; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_dispatch_items ON public.dispatch_items USING btree (dispatch_id);


--
-- Name: idx_downtime_machine_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_downtime_machine_status ON public.machine_downtime USING btree (machine_id, status);


--
-- Name: idx_dt_machine_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_dt_machine_status ON public.machine_downtime USING btree (machine_id, status);


--
-- Name: idx_dt_start_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_dt_start_date ON public.machine_downtime USING btree (start_time DESC);


--
-- Name: idx_fg_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fg_status ON public.finished_goods USING btree (status);


--
-- Name: idx_grn_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_grn_date ON public.grn USING btree (receipt_date);


--
-- Name: idx_grn_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_grn_status ON public.grn USING btree (status);


--
-- Name: idx_issue_items_issue; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_issue_items_issue ON public.yarn_issue_items USING btree (issue_id);


--
-- Name: idx_issue_items_lot; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_issue_items_lot ON public.yarn_issue_items USING btree (lot_id);


--
-- Name: idx_maint_schedule_due; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_maint_schedule_due ON public.maintenance_schedule USING btree (next_due_date);


--
-- Name: idx_maint_schedule_machine; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_maint_schedule_machine ON public.maintenance_schedule USING btree (machine_id);


--
-- Name: idx_movements_lot; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_movements_lot ON public.yarn_lot_movements USING btree (lot_id);


--
-- Name: idx_msl_date_shift; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_msl_date_shift ON public.machine_status_log USING btree (machine_id, date(start_time), shift);


--
-- Name: idx_msl_machine_time; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_msl_machine_time ON public.machine_status_log USING btree (machine_id, start_time DESC);


--
-- Name: idx_partner_roles_pid; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_partner_roles_pid ON public.partner_roles USING btree (partner_id);


--
-- Name: idx_partner_roles_role; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_partner_roles_role ON public.partner_roles USING btree (role);


--
-- Name: idx_partners_code; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_partners_code ON public.partners USING btree (partner_code);


--
-- Name: idx_prod_hist_machine_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_prod_hist_machine_date ON public.production_history USING btree (machine_id, record_date);


--
-- Name: idx_prod_hist_period_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_prod_hist_period_date ON public.production_history USING btree (period_type, record_date);


--
-- Name: idx_rfid_events_time; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_rfid_events_time ON public.rfid_events USING btree (event_time DESC);


--
-- Name: idx_rolls_lot; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_rolls_lot ON public.rolls USING btree (lot_id);


--
-- Name: idx_sl_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_sl_date ON public.stock_ledger USING btree (txn_date);


--
-- Name: idx_sl_doc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_sl_doc ON public.stock_ledger USING btree (doc_type, doc_id);


--
-- Name: idx_sl_item; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_sl_item ON public.stock_ledger USING btree (item_id, txn_date);


--
-- Name: idx_sl_wh; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_sl_wh ON public.stock_ledger USING btree (warehouse_id, txn_date);


--
-- Name: idx_status_log_machine_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_status_log_machine_date ON public.machine_status_log USING btree (machine_id, date(start_time), shift);


--
-- Name: idx_yarn_lots_grn; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_yarn_lots_grn ON public.yarn_lots USING btree (grn_id);


--
-- Name: idx_yarn_lots_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_yarn_lots_status ON public.yarn_lots USING btree (status);


--
-- Name: operators trg_operators_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_operators_updated_at BEFORE UPDATE ON public.operators FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: audit_logs audit_logs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: batch_rolls batch_rolls_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.batch_rolls
    ADD CONSTRAINT batch_rolls_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.batches(batch_id) ON DELETE CASCADE;


--
-- Name: bins bins_rack_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bins
    ADD CONSTRAINT bins_rack_id_fkey FOREIGN KEY (rack_id) REFERENCES public.racks(rack_id);


--
-- Name: bom_lines bom_lines_fabric_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bom_lines
    ADD CONSTRAINT bom_lines_fabric_item_id_fkey FOREIGN KEY (fabric_item_id) REFERENCES public.items(item_id) ON DELETE CASCADE;


--
-- Name: bom_lines bom_lines_yarn_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bom_lines
    ADD CONSTRAINT bom_lines_yarn_item_id_fkey FOREIGN KEY (yarn_item_id) REFERENCES public.items(item_id) ON DELETE CASCADE;


--
-- Name: cost_centres cost_centres_dept_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cost_centres
    ADD CONSTRAINT cost_centres_dept_id_fkey FOREIGN KEY (dept_id) REFERENCES public.departments(dept_id);


--
-- Name: cost_rates cost_rates_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cost_rates
    ADD CONSTRAINT cost_rates_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.items(item_id);


--
-- Name: data_collectors data_collectors_machine_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.data_collectors
    ADD CONSTRAINT data_collectors_machine_id_fkey FOREIGN KEY (machine_id) REFERENCES public.machines(machine_id);


--
-- Name: dispatch_challans dispatch_challans_partner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dispatch_challans
    ADD CONSTRAINT dispatch_challans_partner_id_fkey FOREIGN KEY (partner_id) REFERENCES public.partners(partner_id);


--
-- Name: dispatch_items dispatch_items_dispatch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dispatch_items
    ADD CONSTRAINT dispatch_items_dispatch_id_fkey FOREIGN KEY (dispatch_id) REFERENCES public.dispatch_challans(dispatch_id) ON DELETE CASCADE;


--
-- Name: dispatch_items dispatch_items_fg_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dispatch_items
    ADD CONSTRAINT dispatch_items_fg_id_fkey FOREIGN KEY (fg_id) REFERENCES public.finished_goods(fg_id);


--
-- Name: finished_goods finished_goods_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.finished_goods
    ADD CONSTRAINT finished_goods_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.batches(batch_id);


--
-- Name: finished_goods finished_goods_receipt_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.finished_goods
    ADD CONSTRAINT finished_goods_receipt_id_fkey FOREIGN KEY (receipt_id) REFERENCES public.subcontract_receipts(receipt_id);


--
-- Name: finishing_records finishing_records_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.finishing_records
    ADD CONSTRAINT finishing_records_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.batches(batch_id);


--
-- Name: finishing_records finishing_records_receipt_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.finishing_records
    ADD CONSTRAINT finishing_records_receipt_id_fkey FOREIGN KEY (receipt_id) REFERENCES public.subcontract_receipts(receipt_id);


--
-- Name: grn grn_partner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.grn
    ADD CONSTRAINT grn_partner_id_fkey FOREIGN KEY (partner_id) REFERENCES public.partners(partner_id);


--
-- Name: grn grn_warehouse_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.grn
    ADD CONSTRAINT grn_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES public.warehouses(warehouse_id);


--
-- Name: item_categories item_categories_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.item_categories
    ADD CONSTRAINT item_categories_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.item_categories(category_id);


--
-- Name: item_fabric_attrs item_fabric_attrs_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.item_fabric_attrs
    ADD CONSTRAINT item_fabric_attrs_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.items(item_id) ON DELETE CASCADE;


--
-- Name: item_spare_attrs item_spare_attrs_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.item_spare_attrs
    ADD CONSTRAINT item_spare_attrs_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.items(item_id) ON DELETE CASCADE;


--
-- Name: item_yarn_attrs item_yarn_attrs_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.item_yarn_attrs
    ADD CONSTRAINT item_yarn_attrs_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.items(item_id) ON DELETE CASCADE;


--
-- Name: items items_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.items
    ADD CONSTRAINT items_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.item_categories(category_id);


--
-- Name: items items_hsn_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.items
    ADD CONSTRAINT items_hsn_id_fkey FOREIGN KEY (hsn_id) REFERENCES public.hsn_codes(hsn_id);


--
-- Name: items items_uom_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.items
    ADD CONSTRAINT items_uom_id_fkey FOREIGN KEY (uom_id) REFERENCES public.uom(uom_id);


--
-- Name: machine_downtime machine_downtime_machine_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.machine_downtime
    ADD CONSTRAINT machine_downtime_machine_id_fkey FOREIGN KEY (machine_id) REFERENCES public.machines(machine_id);


--
-- Name: machine_live_data machine_live_data_machine_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.machine_live_data
    ADD CONSTRAINT machine_live_data_machine_id_fkey FOREIGN KEY (machine_id) REFERENCES public.machines(machine_id);


--
-- Name: machine_status_log machine_status_log_machine_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.machine_status_log
    ADD CONSTRAINT machine_status_log_machine_id_fkey FOREIGN KEY (machine_id) REFERENCES public.machines(machine_id);


--
-- Name: machines machines_fabric_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.machines
    ADD CONSTRAINT machines_fabric_code_fkey FOREIGN KEY (fabric_code) REFERENCES public.fabric_types(code) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: maintenance_records maintenance_records_machine_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.maintenance_records
    ADD CONSTRAINT maintenance_records_machine_id_fkey FOREIGN KEY (machine_id) REFERENCES public.machines(machine_id);


--
-- Name: maintenance_schedule maintenance_schedule_machine_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.maintenance_schedule
    ADD CONSTRAINT maintenance_schedule_machine_id_fkey FOREIGN KEY (machine_id) REFERENCES public.machines(machine_id);


--
-- Name: oee_records oee_records_machine_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.oee_records
    ADD CONSTRAINT oee_records_machine_id_fkey FOREIGN KEY (machine_id) REFERENCES public.machines(machine_id);


--
-- Name: partner_addresses partner_addresses_partner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.partner_addresses
    ADD CONSTRAINT partner_addresses_partner_id_fkey FOREIGN KEY (partner_id) REFERENCES public.partners(partner_id) ON DELETE CASCADE;


--
-- Name: partner_bank partner_bank_partner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.partner_bank
    ADD CONSTRAINT partner_bank_partner_id_fkey FOREIGN KEY (partner_id) REFERENCES public.partners(partner_id) ON DELETE CASCADE;


--
-- Name: partner_contacts partner_contacts_partner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.partner_contacts
    ADD CONSTRAINT partner_contacts_partner_id_fkey FOREIGN KEY (partner_id) REFERENCES public.partners(partner_id) ON DELETE CASCADE;


--
-- Name: partner_roles partner_roles_partner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.partner_roles
    ADD CONSTRAINT partner_roles_partner_id_fkey FOREIGN KEY (partner_id) REFERENCES public.partners(partner_id) ON DELETE CASCADE;


--
-- Name: process_route_steps process_route_steps_dept_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.process_route_steps
    ADD CONSTRAINT process_route_steps_dept_id_fkey FOREIGN KEY (dept_id) REFERENCES public.departments(dept_id);


--
-- Name: process_route_steps process_route_steps_route_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.process_route_steps
    ADD CONSTRAINT process_route_steps_route_id_fkey FOREIGN KEY (route_id) REFERENCES public.process_routes(route_id) ON DELETE CASCADE;


--
-- Name: production_records production_records_machine_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.production_records
    ADD CONSTRAINT production_records_machine_id_fkey FOREIGN KEY (machine_id) REFERENCES public.machines(machine_id);


--
-- Name: racks racks_warehouse_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.racks
    ADD CONSTRAINT racks_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES public.warehouses(warehouse_id);


--
-- Name: rolls rolls_fabric_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rolls
    ADD CONSTRAINT rolls_fabric_item_id_fkey FOREIGN KEY (fabric_item_id) REFERENCES public.items(item_id);


--
-- Name: rolls rolls_issue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rolls
    ADD CONSTRAINT rolls_issue_id_fkey FOREIGN KEY (issue_id) REFERENCES public.yarn_issues(issue_id);


--
-- Name: rolls rolls_lot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rolls
    ADD CONSTRAINT rolls_lot_id_fkey FOREIGN KEY (lot_id) REFERENCES public.yarn_lots(lot_id);


--
-- Name: rolls rolls_machine_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rolls
    ADD CONSTRAINT rolls_machine_id_fkey FOREIGN KEY (machine_id) REFERENCES public.machines(machine_id);


--
-- Name: sc_challan_yarn_items sc_challan_yarn_items_challan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sc_challan_yarn_items
    ADD CONSTRAINT sc_challan_yarn_items_challan_id_fkey FOREIGN KEY (challan_id) REFERENCES public.subcontract_challans(challan_id) ON DELETE CASCADE;


--
-- Name: sc_challan_yarn_items sc_challan_yarn_items_lot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sc_challan_yarn_items
    ADD CONSTRAINT sc_challan_yarn_items_lot_id_fkey FOREIGN KEY (lot_id) REFERENCES public.yarn_lots(lot_id);


--
-- Name: stock_ledger stock_ledger_bin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_ledger
    ADD CONSTRAINT stock_ledger_bin_id_fkey FOREIGN KEY (bin_id) REFERENCES public.bins(bin_id);


--
-- Name: stock_ledger stock_ledger_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_ledger
    ADD CONSTRAINT stock_ledger_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.items(item_id);


--
-- Name: stock_ledger stock_ledger_partner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_ledger
    ADD CONSTRAINT stock_ledger_partner_id_fkey FOREIGN KEY (partner_id) REFERENCES public.partners(partner_id);


--
-- Name: stock_ledger stock_ledger_rack_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_ledger
    ADD CONSTRAINT stock_ledger_rack_id_fkey FOREIGN KEY (rack_id) REFERENCES public.racks(rack_id);


--
-- Name: stock_ledger stock_ledger_warehouse_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_ledger
    ADD CONSTRAINT stock_ledger_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES public.warehouses(warehouse_id);


--
-- Name: subcontract_challan_items subcontract_challan_items_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subcontract_challan_items
    ADD CONSTRAINT subcontract_challan_items_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.batches(batch_id);


--
-- Name: subcontract_challan_items subcontract_challan_items_challan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subcontract_challan_items
    ADD CONSTRAINT subcontract_challan_items_challan_id_fkey FOREIGN KEY (challan_id) REFERENCES public.subcontract_challans(challan_id) ON DELETE CASCADE;


--
-- Name: subcontract_challans subcontract_challans_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subcontract_challans
    ADD CONSTRAINT subcontract_challans_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.batches(batch_id);


--
-- Name: subcontract_challans subcontract_challans_forwarded_from_challan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subcontract_challans
    ADD CONSTRAINT subcontract_challans_forwarded_from_challan_id_fkey FOREIGN KEY (forwarded_from_challan_id) REFERENCES public.subcontract_challans(challan_id);


--
-- Name: subcontract_challans subcontract_challans_partner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subcontract_challans
    ADD CONSTRAINT subcontract_challans_partner_id_fkey FOREIGN KEY (partner_id) REFERENCES public.partners(partner_id);


--
-- Name: subcontract_receipt_items subcontract_receipt_items_receipt_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subcontract_receipt_items
    ADD CONSTRAINT subcontract_receipt_items_receipt_id_fkey FOREIGN KEY (receipt_id) REFERENCES public.subcontract_receipts(receipt_id) ON DELETE CASCADE;


--
-- Name: subcontract_receipts subcontract_receipts_challan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subcontract_receipts
    ADD CONSTRAINT subcontract_receipts_challan_id_fkey FOREIGN KEY (challan_id) REFERENCES public.subcontract_challans(challan_id);


--
-- Name: yarn_issue_items yarn_issue_items_issue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.yarn_issue_items
    ADD CONSTRAINT yarn_issue_items_issue_id_fkey FOREIGN KEY (issue_id) REFERENCES public.yarn_issues(issue_id) ON DELETE CASCADE;


--
-- Name: yarn_issue_items yarn_issue_items_lot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.yarn_issue_items
    ADD CONSTRAINT yarn_issue_items_lot_id_fkey FOREIGN KEY (lot_id) REFERENCES public.yarn_lots(lot_id);


--
-- Name: yarn_issues yarn_issues_cost_centre_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.yarn_issues
    ADD CONSTRAINT yarn_issues_cost_centre_id_fkey FOREIGN KEY (cost_centre_id) REFERENCES public.cost_centres(cc_id);


--
-- Name: yarn_lot_movements yarn_lot_movements_lot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.yarn_lot_movements
    ADD CONSTRAINT yarn_lot_movements_lot_id_fkey FOREIGN KEY (lot_id) REFERENCES public.yarn_lots(lot_id);


--
-- Name: yarn_lots yarn_lots_grn_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.yarn_lots
    ADD CONSTRAINT yarn_lots_grn_id_fkey FOREIGN KEY (grn_id) REFERENCES public.grn(grn_id) ON DELETE CASCADE;


--
-- Name: yarn_lots yarn_lots_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.yarn_lots
    ADD CONSTRAINT yarn_lots_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.items(item_id);


--
-- PostgreSQL database dump complete
--

\unrestrict LKnnp2RKK98KuRpbFwjtrxF7TkMBAcvZbWggjahvEwz68t8kAK265A0A7qNoXDA


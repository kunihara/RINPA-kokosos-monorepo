


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE OR REPLACE FUNCTION "public"."purge_old_data"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
begin
  delete from locations where captured_at < now() - interval '48 hours';
  delete from deliveries where created_at < now() - interval '48 hours';
  delete from alerts where coalesce(ended_at, started_at) < now() - interval '48 hours';
end;$$;


ALTER FUNCTION "public"."purge_old_data"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."alert_recipients" (
    "alert_id" "uuid" NOT NULL,
    "contact_id" "uuid" NOT NULL,
    "email" "text" NOT NULL,
    "purpose" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "alert_recipients_purpose_check" CHECK (("purpose" = ANY (ARRAY['start'::"text", 'arrival'::"text"])))
);


ALTER TABLE "public"."alert_recipients" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."alerts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "type" "text" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "started_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "ended_at" timestamp with time zone,
    "max_duration_sec" integer DEFAULT 3600 NOT NULL,
    "revoked_at" timestamp with time zone,
    CONSTRAINT "alerts_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'ended'::"text", 'timeout'::"text"]))),
    CONSTRAINT "alerts_type_check" CHECK (("type" = ANY (ARRAY['emergency'::"text", 'going_home'::"text"])))
);


ALTER TABLE "public"."alerts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."contact_verifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "contact_id" "uuid" NOT NULL,
    "token_hash" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "used_at" timestamp with time zone,
    "expires_at" timestamp with time zone
);


ALTER TABLE "public"."contact_verifications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."contacts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "email" "text" NOT NULL,
    "role" "text",
    "capabilities" "jsonb" DEFAULT '{}'::"jsonb",
    "verified_at" timestamp with time zone
);


ALTER TABLE "public"."contacts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."deliveries" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "alert_id" "uuid" NOT NULL,
    "contact_id" "uuid" NOT NULL,
    "channel" "text" NOT NULL,
    "status" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "deliveries_channel_check" CHECK (("channel" = ANY (ARRAY['push'::"text", 'email'::"text"])))
);


ALTER TABLE "public"."deliveries" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."locations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "alert_id" "uuid" NOT NULL,
    "lat" double precision NOT NULL,
    "lng" double precision NOT NULL,
    "accuracy_m" double precision,
    "battery_pct" integer,
    "captured_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."locations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."reactions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "alert_id" "uuid" NOT NULL,
    "contact_id" "uuid" NOT NULL,
    "preset" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."reactions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."revocations" (
    "alert_id" "uuid" NOT NULL,
    "revoked_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."revocations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."users" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "apple_sub" "text",
    "apns_token" "text",
    "email" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."users" OWNER TO "postgres";


ALTER TABLE ONLY "public"."alert_recipients"
    ADD CONSTRAINT "alert_recipients_pkey" PRIMARY KEY ("alert_id", "contact_id", "purpose");



ALTER TABLE ONLY "public"."alerts"
    ADD CONSTRAINT "alerts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."contact_verifications"
    ADD CONSTRAINT "contact_verifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."contacts"
    ADD CONSTRAINT "contacts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."deliveries"
    ADD CONSTRAINT "deliveries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."locations"
    ADD CONSTRAINT "locations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."reactions"
    ADD CONSTRAINT "reactions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."revocations"
    ADD CONSTRAINT "revocations_pkey" PRIMARY KEY ("alert_id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_apple_sub_key" UNIQUE ("apple_sub");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_contact_verifications_contact" ON "public"."contact_verifications" USING "btree" ("contact_id");



CREATE INDEX "idx_locations_alert_time" ON "public"."locations" USING "btree" ("alert_id", "captured_at" DESC);



CREATE INDEX "idx_reactions_alert_time" ON "public"."reactions" USING "btree" ("alert_id", "created_at" DESC);



ALTER TABLE ONLY "public"."alert_recipients"
    ADD CONSTRAINT "alert_recipients_alert_id_fkey" FOREIGN KEY ("alert_id") REFERENCES "public"."alerts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."alert_recipients"
    ADD CONSTRAINT "alert_recipients_contact_id_fkey" FOREIGN KEY ("contact_id") REFERENCES "public"."contacts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."alerts"
    ADD CONSTRAINT "alerts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."contact_verifications"
    ADD CONSTRAINT "contact_verifications_contact_id_fkey" FOREIGN KEY ("contact_id") REFERENCES "public"."contacts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."contacts"
    ADD CONSTRAINT "contacts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."deliveries"
    ADD CONSTRAINT "deliveries_alert_id_fkey" FOREIGN KEY ("alert_id") REFERENCES "public"."alerts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."deliveries"
    ADD CONSTRAINT "deliveries_contact_id_fkey" FOREIGN KEY ("contact_id") REFERENCES "public"."contacts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."locations"
    ADD CONSTRAINT "locations_alert_id_fkey" FOREIGN KEY ("alert_id") REFERENCES "public"."alerts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."reactions"
    ADD CONSTRAINT "reactions_alert_id_fkey" FOREIGN KEY ("alert_id") REFERENCES "public"."alerts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."revocations"
    ADD CONSTRAINT "revocations_alert_id_fkey" FOREIGN KEY ("alert_id") REFERENCES "public"."alerts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_auth_fk" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE "public"."alerts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."contacts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."deliveries" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."locations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."revocations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."users" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."purge_old_data"() TO "anon";
GRANT ALL ON FUNCTION "public"."purge_old_data"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."purge_old_data"() TO "service_role";



GRANT ALL ON TABLE "public"."alert_recipients" TO "anon";
GRANT ALL ON TABLE "public"."alert_recipients" TO "authenticated";
GRANT ALL ON TABLE "public"."alert_recipients" TO "service_role";



GRANT ALL ON TABLE "public"."alerts" TO "anon";
GRANT ALL ON TABLE "public"."alerts" TO "authenticated";
GRANT ALL ON TABLE "public"."alerts" TO "service_role";



GRANT ALL ON TABLE "public"."contact_verifications" TO "anon";
GRANT ALL ON TABLE "public"."contact_verifications" TO "authenticated";
GRANT ALL ON TABLE "public"."contact_verifications" TO "service_role";



GRANT ALL ON TABLE "public"."contacts" TO "anon";
GRANT ALL ON TABLE "public"."contacts" TO "authenticated";
GRANT ALL ON TABLE "public"."contacts" TO "service_role";



GRANT ALL ON TABLE "public"."deliveries" TO "anon";
GRANT ALL ON TABLE "public"."deliveries" TO "authenticated";
GRANT ALL ON TABLE "public"."deliveries" TO "service_role";



GRANT ALL ON TABLE "public"."locations" TO "anon";
GRANT ALL ON TABLE "public"."locations" TO "authenticated";
GRANT ALL ON TABLE "public"."locations" TO "service_role";



GRANT ALL ON TABLE "public"."reactions" TO "anon";
GRANT ALL ON TABLE "public"."reactions" TO "authenticated";
GRANT ALL ON TABLE "public"."reactions" TO "service_role";



GRANT ALL ON TABLE "public"."revocations" TO "anon";
GRANT ALL ON TABLE "public"."revocations" TO "authenticated";
GRANT ALL ON TABLE "public"."revocations" TO "service_role";



GRANT ALL ON TABLE "public"."users" TO "anon";
GRANT ALL ON TABLE "public"."users" TO "authenticated";
GRANT ALL ON TABLE "public"."users" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";







RESET ALL;

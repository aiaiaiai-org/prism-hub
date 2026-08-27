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
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: capability_grants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.capability_grants (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    service_principal_id uuid NOT NULL,
    capability character varying(128) NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: channel_grants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channel_grants (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    service_principal_id uuid NOT NULL,
    channel_id character varying(128) NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: client_credentials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.client_credentials (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    service_principal_id uuid NOT NULL,
    token_digest character varying(64) NOT NULL,
    expires_at timestamp(6) without time zone,
    revoked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT client_credentials_digest_check CHECK (((token_digest)::text ~ '^[0-9a-f]{64}$'::text))
);


--
-- Name: provider_identity_bindings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.provider_identity_bindings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_identity_id uuid NOT NULL,
    provider character varying(64) NOT NULL,
    provider_scope character varying(128) NOT NULL,
    subject_id character varying(512) NOT NULL,
    status character varying(32) DEFAULT 'active'::character varying NOT NULL,
    revoked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT provider_identity_bindings_provider_check CHECK (((provider)::text ~ '^[a-z][a-z0-9._-]{0,63}$'::text)),
    CONSTRAINT provider_identity_bindings_scope_check CHECK (((provider_scope)::text ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'::text)),
    CONSTRAINT provider_identity_bindings_state_check CHECK (((((status)::text = 'active'::text) AND (revoked_at IS NULL)) OR (((status)::text = 'revoked'::text) AND (revoked_at IS NOT NULL)))),
    CONSTRAINT provider_identity_bindings_status_check CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('revoked'::character varying)::text]))),
    CONSTRAINT provider_identity_bindings_subject_check CHECK ((char_length((subject_id)::text) > 0))
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: service_principals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.service_principals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    identifier character varying(128) NOT NULL,
    bot_instance_id character varying(128) NOT NULL,
    status character varying(32) DEFAULT 'active'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT service_principals_status_check CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('disabled'::character varying)::text])))
);


--
-- Name: user_identities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_identities (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    canonical_type character varying(32) NOT NULL,
    canonical_id character varying(255) NOT NULL,
    status character varying(32) DEFAULT 'active'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT user_identities_canonical_id_check CHECK (((char_length((canonical_id)::text) >= 1) AND (char_length((canonical_id)::text) <= 255))),
    CONSTRAINT user_identities_canonical_type_check CHECK (((canonical_type)::text = 'person'::text)),
    CONSTRAINT user_identities_status_check CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('disabled'::character varying)::text])))
);


--
-- Name: workspace_memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workspace_memberships (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    user_identity_id uuid NOT NULL,
    role character varying(32) NOT NULL,
    status character varying(32) DEFAULT 'active'::character varying NOT NULL,
    revoked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT workspace_memberships_role_check CHECK (((role)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'member'::character varying])::text[]))),
    CONSTRAINT workspace_memberships_state_check CHECK (((((status)::text = 'active'::text) AND (revoked_at IS NULL)) OR (((status)::text = 'revoked'::text) AND (revoked_at IS NOT NULL)))),
    CONSTRAINT workspace_memberships_status_check CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'revoked'::character varying])::text[])))
);


--
-- Name: workspaces; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workspaces (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    identifier character varying(128) NOT NULL,
    status character varying(32) DEFAULT 'active'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT workspaces_status_check CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('disabled'::character varying)::text])))
);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: capability_grants capability_grants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.capability_grants
    ADD CONSTRAINT capability_grants_pkey PRIMARY KEY (id);


--
-- Name: channel_grants channel_grants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_grants
    ADD CONSTRAINT channel_grants_pkey PRIMARY KEY (id);


--
-- Name: client_credentials client_credentials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_credentials
    ADD CONSTRAINT client_credentials_pkey PRIMARY KEY (id);


--
-- Name: provider_identity_bindings provider_identity_bindings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_identity_bindings
    ADD CONSTRAINT provider_identity_bindings_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: service_principals service_principals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_principals
    ADD CONSTRAINT service_principals_pkey PRIMARY KEY (id);


--
-- Name: user_identities user_identities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_identities
    ADD CONSTRAINT user_identities_pkey PRIMARY KEY (id);


--
-- Name: workspace_memberships workspace_memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_memberships
    ADD CONSTRAINT workspace_memberships_pkey PRIMARY KEY (id);


--
-- Name: workspaces workspaces_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspaces
    ADD CONSTRAINT workspaces_pkey PRIMARY KEY (id);


--
-- Name: idx_provider_identity_bindings_subject; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_provider_identity_bindings_subject ON public.provider_identity_bindings USING btree (provider, provider_scope, subject_id);


--
-- Name: idx_workspace_memberships_workspace_user; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_workspace_memberships_workspace_user ON public.workspace_memberships USING btree (workspace_id, user_identity_id);


--
-- Name: index_capability_grants_on_service_principal_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_capability_grants_on_service_principal_id ON public.capability_grants USING btree (service_principal_id);


--
-- Name: index_capability_grants_on_service_principal_id_and_capability; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_capability_grants_on_service_principal_id_and_capability ON public.capability_grants USING btree (service_principal_id, capability);


--
-- Name: index_channel_grants_on_service_principal_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_channel_grants_on_service_principal_id ON public.channel_grants USING btree (service_principal_id);


--
-- Name: index_channel_grants_on_service_principal_id_and_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_channel_grants_on_service_principal_id_and_channel_id ON public.channel_grants USING btree (service_principal_id, channel_id);


--
-- Name: index_client_credentials_on_service_principal_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_client_credentials_on_service_principal_id ON public.client_credentials USING btree (service_principal_id);


--
-- Name: index_client_credentials_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_client_credentials_on_token_digest ON public.client_credentials USING btree (token_digest);


--
-- Name: index_provider_identity_bindings_on_user_identity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_provider_identity_bindings_on_user_identity_id ON public.provider_identity_bindings USING btree (user_identity_id);


--
-- Name: index_service_principals_on_workspace_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_service_principals_on_workspace_id ON public.service_principals USING btree (workspace_id);


--
-- Name: index_service_principals_on_workspace_id_and_bot_instance_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_service_principals_on_workspace_id_and_bot_instance_id ON public.service_principals USING btree (workspace_id, bot_instance_id);


--
-- Name: index_service_principals_on_workspace_id_and_identifier; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_service_principals_on_workspace_id_and_identifier ON public.service_principals USING btree (workspace_id, identifier);


--
-- Name: index_user_identities_on_canonical_type_and_canonical_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_user_identities_on_canonical_type_and_canonical_id ON public.user_identities USING btree (canonical_type, canonical_id);


--
-- Name: index_workspace_memberships_on_user_identity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_workspace_memberships_on_user_identity_id ON public.workspace_memberships USING btree (user_identity_id);


--
-- Name: index_workspace_memberships_on_workspace_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_workspace_memberships_on_workspace_id ON public.workspace_memberships USING btree (workspace_id);


--
-- Name: index_workspaces_on_identifier; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_workspaces_on_identifier ON public.workspaces USING btree (identifier);


--
-- Name: workspace_memberships fk_rails_26c4c0bd41; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_memberships
    ADD CONSTRAINT fk_rails_26c4c0bd41 FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE RESTRICT;


--
-- Name: client_credentials fk_rails_458e35f9f8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_credentials
    ADD CONSTRAINT fk_rails_458e35f9f8 FOREIGN KEY (service_principal_id) REFERENCES public.service_principals(id) ON DELETE CASCADE;


--
-- Name: channel_grants fk_rails_7d12b56971; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_grants
    ADD CONSTRAINT fk_rails_7d12b56971 FOREIGN KEY (service_principal_id) REFERENCES public.service_principals(id) ON DELETE CASCADE;


--
-- Name: capability_grants fk_rails_7db71f7581; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.capability_grants
    ADD CONSTRAINT fk_rails_7db71f7581 FOREIGN KEY (service_principal_id) REFERENCES public.service_principals(id) ON DELETE CASCADE;


--
-- Name: workspace_memberships fk_rails_7e8947d8a0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_memberships
    ADD CONSTRAINT fk_rails_7e8947d8a0 FOREIGN KEY (user_identity_id) REFERENCES public.user_identities(id) ON DELETE RESTRICT;


--
-- Name: service_principals fk_rails_a2c5538b21; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_principals
    ADD CONSTRAINT fk_rails_a2c5538b21 FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE RESTRICT;


--
-- Name: provider_identity_bindings fk_rails_bbe051879c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_identity_bindings
    ADD CONSTRAINT fk_rails_bbe051879c FOREIGN KEY (user_identity_id) REFERENCES public.user_identities(id) ON DELETE RESTRICT;


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260827154500'),
('20260827134500'),
('20260827112400'),
('20260827094700');


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
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: protect_social_account_access_history(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.protect_social_account_access_history() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'social account access must be revoked, not deleted'
      USING ERRCODE = '23514', CONSTRAINT = 'social_account_accesses_retained_history';
  END IF;
  IF ROW(NEW.id, NEW.social_account_id, NEW.user_identity_id, NEW.role, NEW.created_at)
    IS DISTINCT FROM ROW(OLD.id, OLD.social_account_id, OLD.user_identity_id, OLD.role, OLD.created_at) THEN
    RAISE EXCEPTION 'social account access identity and role are immutable'
      USING ERRCODE = '23514', CONSTRAINT = 'social_account_accesses_immutable_grant';
  END IF;
  IF OLD.status = 'revoked' AND
    ROW(NEW.status, NEW.revoked_at) IS DISTINCT FROM ROW(OLD.status, OLD.revoked_at) THEN
    RAISE EXCEPTION 'social account access revocation is final'
      USING ERRCODE = '23514', CONSTRAINT = 'social_account_accesses_final_revocation';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: protect_social_account_key(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.protect_social_account_key() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF ROW(NEW.id, NEW.provider, NEW.provider_account_id)
    IS DISTINCT FROM ROW(OLD.id, OLD.provider, OLD.provider_account_id) THEN
    RAISE EXCEPTION 'social account identity is immutable'
      USING ERRCODE = '23514', CONSTRAINT = 'social_accounts_immutable_key';
  END IF;
  RETURN NEW;
END;
$$;


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
-- Name: bot_instance_lifecycle_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bot_instance_lifecycle_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    bot_instance_id uuid NOT NULL,
    actor_user_identity_id uuid NOT NULL,
    action character varying(32) NOT NULL,
    from_status character varying(32),
    to_status character varying(32) NOT NULL,
    occurred_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT bot_instance_events_action_check CHECK (((action)::text = ANY (ARRAY[('created'::character varying)::text, ('paused'::character varying)::text, ('resumed'::character varying)::text]))),
    CONSTRAINT bot_instance_events_from_status_check CHECK (((from_status IS NULL) OR ((from_status)::text = ANY (ARRAY[('active'::character varying)::text, ('paused'::character varying)::text, ('disabled'::character varying)::text])))),
    CONSTRAINT bot_instance_events_to_status_check CHECK (((to_status)::text = ANY (ARRAY[('active'::character varying)::text, ('paused'::character varying)::text, ('disabled'::character varying)::text]))),
    CONSTRAINT bot_instance_events_transition_check CHECK (((((action)::text = 'created'::text) AND (from_status IS NULL) AND ((to_status)::text = 'active'::text)) OR (((action)::text = 'paused'::text) AND ((from_status)::text = 'active'::text) AND ((to_status)::text = 'paused'::text)) OR (((action)::text = 'resumed'::text) AND ((from_status)::text = 'paused'::text) AND ((to_status)::text = 'active'::text))))
);


--
-- Name: bot_instances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bot_instances (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    service_principal_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    status character varying(32) DEFAULT 'active'::character varying NOT NULL,
    paused_at timestamp(6) without time zone,
    disabled_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT bot_instances_state_check CHECK (((((status)::text = 'active'::text) AND (paused_at IS NULL) AND (disabled_at IS NULL)) OR (((status)::text = 'paused'::text) AND (paused_at IS NOT NULL) AND (disabled_at IS NULL)) OR (((status)::text = 'disabled'::text) AND (paused_at IS NULL) AND (disabled_at IS NOT NULL)))),
    CONSTRAINT bot_instances_status_check CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('paused'::character varying)::text, ('disabled'::character varying)::text])))
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
-- Name: delivery_outbox_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.delivery_outbox_entries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace character varying(100) NOT NULL,
    logical_channel character varying(100) NOT NULL,
    idempotency_key character varying(64) NOT NULL,
    intent_payload jsonb NOT NULL,
    status character varying(16) DEFAULT 'pending'::character varying NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    available_at timestamp(6) without time zone NOT NULL,
    locked_at timestamp(6) without time zone,
    lock_token character varying(64),
    delivered_at timestamp(6) without time zone,
    failed_at timestamp(6) without time zone,
    last_error_code character varying(160),
    last_error_details jsonb,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT delivery_outbox_entries_attempts_check CHECK ((attempts >= 0)),
    CONSTRAINT delivery_outbox_entries_channel_check CHECK (((char_length(btrim((logical_channel)::text)) >= 1) AND (char_length(btrim((logical_channel)::text)) <= 100))),
    CONSTRAINT delivery_outbox_entries_delivered_at_check CHECK (((((status)::text = 'delivered'::text) AND (delivered_at IS NOT NULL)) OR ((status)::text <> 'delivered'::text))),
    CONSTRAINT delivery_outbox_entries_idempotency_key_check CHECK (((idempotency_key)::text ~ '^[0-9a-f]{64}$'::text)),
    CONSTRAINT delivery_outbox_entries_processing_lock_check CHECK (((((status)::text = 'processing'::text) AND (locked_at IS NOT NULL) AND (lock_token IS NOT NULL)) OR ((status)::text <> 'processing'::text))),
    CONSTRAINT delivery_outbox_entries_status_check CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'processing'::character varying, 'delivered'::character varying, 'failed'::character varying])::text[]))),
    CONSTRAINT delivery_outbox_entries_workspace_check CHECK (((char_length(btrim((workspace)::text)) >= 1) AND (char_length(btrim((workspace)::text)) <= 100)))
);


--
-- Name: mail_provider_credentials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mail_provider_credentials (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    provider character varying(64) NOT NULL,
    origin character varying(2048) NOT NULL,
    resource character varying(2048) NOT NULL,
    access_token_ciphertext text NOT NULL,
    refresh_token_ciphertext text,
    scope text NOT NULL,
    token_type character varying(32) NOT NULL,
    expires_at timestamp(6) without time zone,
    status character varying(32) DEFAULT 'active'::character varying NOT NULL,
    revoked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    oauth_client_id character varying(255),
    CONSTRAINT mail_provider_credentials_access_token_check CHECK ((char_length(access_token_ciphertext) > 0)),
    CONSTRAINT mail_provider_credentials_oauth_client_id_check CHECK (((oauth_client_id IS NULL) OR (char_length((oauth_client_id)::text) > 0))),
    CONSTRAINT mail_provider_credentials_origin_check CHECK (((origin)::text ~ '^https://[^/]+$'::text)),
    CONSTRAINT mail_provider_credentials_provider_check CHECK (((provider)::text ~ '^[a-z][a-z0-9._-]{0,63}$'::text)),
    CONSTRAINT mail_provider_credentials_refresh_token_check CHECK (((refresh_token_ciphertext IS NULL) OR (char_length(refresh_token_ciphertext) > 0))),
    CONSTRAINT mail_provider_credentials_resource_check CHECK (((resource)::text ~ '^https://[^/]+/api/v[0-9]+$'::text)),
    CONSTRAINT mail_provider_credentials_scope_check CHECK ((char_length(scope) > 0)),
    CONSTRAINT mail_provider_credentials_state_check CHECK (((((status)::text = 'active'::text) AND (revoked_at IS NULL)) OR (((status)::text = 'revoked'::text) AND (revoked_at IS NOT NULL)))),
    CONSTRAINT mail_provider_credentials_status_check CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('revoked'::character varying)::text]))),
    CONSTRAINT mail_provider_credentials_token_type_check CHECK ((char_length((token_type)::text) > 0))
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
    legacy_workspace_id uuid,
    identifier character varying(128) NOT NULL,
    legacy_bot_instance_id character varying(128),
    status character varying(32) DEFAULT 'active'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT service_principals_status_check CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('disabled'::character varying)::text])))
);


--
-- Name: social_account_accesses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.social_account_accesses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    social_account_id uuid NOT NULL,
    user_identity_id uuid NOT NULL,
    role character varying(32) NOT NULL,
    status character varying(32) DEFAULT 'active'::character varying NOT NULL,
    revoked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT social_account_accesses_role_check CHECK (((role)::text = ANY (ARRAY[('owner'::character varying)::text, ('manager'::character varying)::text, ('publisher'::character varying)::text]))),
    CONSTRAINT social_account_accesses_state_check CHECK (((((status)::text = 'active'::text) AND (revoked_at IS NULL)) OR (((status)::text = 'revoked'::text) AND (revoked_at IS NOT NULL)))),
    CONSTRAINT social_account_accesses_status_check CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('revoked'::character varying)::text])))
);


--
-- Name: social_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.social_accounts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    provider character varying(64) NOT NULL,
    provider_account_id character varying(512) NOT NULL,
    username character varying(255),
    display_name character varying(255),
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT social_accounts_account_id_control_check CHECK (((provider_account_id)::text !~ '[[:cntrl:]]'::text)),
    CONSTRAINT social_accounts_display_name_check CHECK (((display_name IS NULL) OR (char_length((display_name)::text) > 0))),
    CONSTRAINT social_accounts_provider_account_id_check CHECK ((char_length((provider_account_id)::text) > 0)),
    CONSTRAINT social_accounts_provider_check CHECK (((provider)::text ~ '^[a-z][a-z0-9._-]{0,63}$'::text)),
    CONSTRAINT social_accounts_username_check CHECK (((username IS NULL) OR (char_length((username)::text) > 0)))
);


--
-- Name: telegram_surface_bindings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.telegram_surface_bindings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    bot_instance_id uuid NOT NULL,
    logical_channel character varying(100) NOT NULL,
    chat_id bigint NOT NULL,
    message_thread_id bigint,
    created_by_user_identity_id uuid NOT NULL,
    status character varying(16) DEFAULT 'active'::character varying NOT NULL,
    revoked_at timestamp(6) without time zone,
    revoked_by_user_identity_id uuid,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT telegram_surface_bindings_chat_id_check CHECK ((chat_id <> 0)),
    CONSTRAINT telegram_surface_bindings_logical_channel_check CHECK (((char_length(btrim((logical_channel)::text)) >= 1) AND (char_length(btrim((logical_channel)::text)) <= 100))),
    CONSTRAINT telegram_surface_bindings_state_check CHECK (((((status)::text = 'active'::text) AND (revoked_at IS NULL) AND (revoked_by_user_identity_id IS NULL)) OR (((status)::text = 'revoked'::text) AND (revoked_at IS NOT NULL) AND (revoked_by_user_identity_id IS NOT NULL)))),
    CONSTRAINT telegram_surface_bindings_status_check CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'revoked'::character varying])::text[]))),
    CONSTRAINT telegram_surface_bindings_thread_id_check CHECK (((message_thread_id IS NULL) OR (message_thread_id > 0)))
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
    CONSTRAINT user_identities_canonical_id_check CHECK ((((canonical_type)::text <> 'person'::text) OR (("left"((canonical_id)::text, 2) = '0x'::text) AND ((char_length(SUBSTRING(canonical_id FROM 3)) >= 2) AND (char_length(SUBSTRING(canonical_id FROM 3)) <= 32)) AND (translate(SUBSTRING(canonical_id FROM 3), 'abcdefghijklmnopqrstuvwxyz0123456789-/:;()₴&@".,?!''[]{}#%^*+=_\|~<>€$£•'::text, ''::text) = ''::text)))),
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
    CONSTRAINT workspace_memberships_role_check CHECK (((role)::text = ANY (ARRAY[('owner'::character varying)::text, ('admin'::character varying)::text, ('member'::character varying)::text]))),
    CONSTRAINT workspace_memberships_state_check CHECK (((((status)::text = 'active'::text) AND (revoked_at IS NULL)) OR (((status)::text = 'revoked'::text) AND (revoked_at IS NOT NULL)))),
    CONSTRAINT workspace_memberships_status_check CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('revoked'::character varying)::text])))
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
-- Name: bot_instance_lifecycle_events bot_instance_lifecycle_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bot_instance_lifecycle_events
    ADD CONSTRAINT bot_instance_lifecycle_events_pkey PRIMARY KEY (id);


--
-- Name: bot_instances bot_instances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bot_instances
    ADD CONSTRAINT bot_instances_pkey PRIMARY KEY (id);


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
-- Name: delivery_outbox_entries delivery_outbox_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_outbox_entries
    ADD CONSTRAINT delivery_outbox_entries_pkey PRIMARY KEY (id);


--
-- Name: mail_provider_credentials mail_provider_credentials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mail_provider_credentials
    ADD CONSTRAINT mail_provider_credentials_pkey PRIMARY KEY (id);


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
-- Name: social_account_accesses social_account_accesses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.social_account_accesses
    ADD CONSTRAINT social_account_accesses_pkey PRIMARY KEY (id);


--
-- Name: social_accounts social_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.social_accounts
    ADD CONSTRAINT social_accounts_pkey PRIMARY KEY (id);


--
-- Name: telegram_surface_bindings telegram_surface_bindings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telegram_surface_bindings
    ADD CONSTRAINT telegram_surface_bindings_pkey PRIMARY KEY (id);


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
-- Name: idx_bot_instance_events_instance_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bot_instance_events_instance_time ON public.bot_instance_lifecycle_events USING btree (bot_instance_id, occurred_at);


--
-- Name: idx_bot_instances_principal_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_bot_instances_principal_workspace ON public.bot_instances USING btree (service_principal_id, workspace_id);


--
-- Name: idx_delivery_outbox_due; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_delivery_outbox_due ON public.delivery_outbox_entries USING btree (status, available_at);


--
-- Name: idx_delivery_outbox_lock_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_delivery_outbox_lock_token ON public.delivery_outbox_entries USING btree (lock_token) WHERE (lock_token IS NOT NULL);


--
-- Name: idx_mail_provider_credentials_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_mail_provider_credentials_identity ON public.mail_provider_credentials USING btree (provider, origin, resource);


--
-- Name: idx_provider_identity_bindings_subject; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_provider_identity_bindings_subject ON public.provider_identity_bindings USING btree (provider, provider_scope, subject_id);


--
-- Name: idx_social_account_accesses_account_user; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_social_account_accesses_account_user ON public.social_account_accesses USING btree (social_account_id, user_identity_id);


--
-- Name: idx_social_accounts_provider_account; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_social_accounts_provider_account ON public.social_accounts USING btree (provider, provider_account_id);


--
-- Name: idx_tg_surface_bindings_active_logical; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_tg_surface_bindings_active_logical ON public.telegram_surface_bindings USING btree (workspace_id, logical_channel) WHERE ((status)::text = 'active'::text);


--
-- Name: idx_tg_surface_bindings_active_root; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_tg_surface_bindings_active_root ON public.telegram_surface_bindings USING btree (bot_instance_id, chat_id) WHERE (((status)::text = 'active'::text) AND (message_thread_id IS NULL));


--
-- Name: idx_tg_surface_bindings_active_topic; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_tg_surface_bindings_active_topic ON public.telegram_surface_bindings USING btree (bot_instance_id, chat_id, message_thread_id) WHERE (((status)::text = 'active'::text) AND (message_thread_id IS NOT NULL));


--
-- Name: idx_workspace_memberships_workspace_user; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_workspace_memberships_workspace_user ON public.workspace_memberships USING btree (workspace_id, user_identity_id);


--
-- Name: index_bot_instance_lifecycle_events_on_actor_user_identity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_bot_instance_lifecycle_events_on_actor_user_identity_id ON public.bot_instance_lifecycle_events USING btree (actor_user_identity_id);


--
-- Name: index_bot_instance_lifecycle_events_on_bot_instance_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_bot_instance_lifecycle_events_on_bot_instance_id ON public.bot_instance_lifecycle_events USING btree (bot_instance_id);


--
-- Name: index_bot_instances_on_service_principal_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_bot_instances_on_service_principal_id ON public.bot_instances USING btree (service_principal_id);


--
-- Name: index_bot_instances_on_workspace_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_bot_instances_on_workspace_id ON public.bot_instances USING btree (service_principal_id);


--
-- Name: index_bot_instances_on_workspace_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_bot_instances_on_workspace_id ON public.bot_instances USING btree (workspace_id);


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
-- Name: index_delivery_outbox_entries_on_idempotency_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_delivery_outbox_entries_on_idempotency_key ON public.delivery_outbox_entries USING btree (idempotency_key);


--
-- Name: index_provider_identity_bindings_on_user_identity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_provider_identity_bindings_on_user_identity_id ON public.provider_identity_bindings USING btree (user_identity_id);


--
-- Name: index_service_principals_on_identifier; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_service_principals_on_identifier ON public.service_principals USING btree (identifier);


--
-- Name: index_service_principals_on_legacy_workspace_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_service_principals_on_legacy_workspace_id ON public.service_principals USING btree (legacy_workspace_id);


--
-- Name: index_social_account_accesses_on_social_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_social_account_accesses_on_social_account_id ON public.social_account_accesses USING btree (social_account_id);


--
-- Name: index_social_account_accesses_on_user_identity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_social_account_accesses_on_user_identity_id ON public.social_account_accesses USING btree (user_identity_id);


--
-- Name: index_telegram_surface_bindings_on_bot_instance_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_telegram_surface_bindings_on_bot_instance_id ON public.telegram_surface_bindings USING btree (bot_instance_id);


--
-- Name: index_telegram_surface_bindings_on_created_by_user_identity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_telegram_surface_bindings_on_created_by_user_identity_id ON public.telegram_surface_bindings USING btree (created_by_user_identity_id);


--
-- Name: index_telegram_surface_bindings_on_revoked_by_user_identity_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_telegram_surface_bindings_on_revoked_by_user_identity_id ON public.telegram_surface_bindings USING btree (revoked_by_user_identity_id);


--
-- Name: index_telegram_surface_bindings_on_workspace_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_telegram_surface_bindings_on_workspace_id ON public.telegram_surface_bindings USING btree (workspace_id);


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
-- Name: social_account_accesses social_account_accesses_protect_history; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER social_account_accesses_protect_history BEFORE DELETE OR UPDATE ON public.social_account_accesses FOR EACH ROW EXECUTE FUNCTION public.protect_social_account_access_history();


--
-- Name: social_accounts social_accounts_protect_key; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER social_accounts_protect_key BEFORE UPDATE ON public.social_accounts FOR EACH ROW EXECUTE FUNCTION public.protect_social_account_key();


--
-- Name: telegram_surface_bindings fk_rails_0e5d8d6780; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telegram_surface_bindings
    ADD CONSTRAINT fk_rails_0e5d8d6780 FOREIGN KEY (created_by_user_identity_id) REFERENCES public.user_identities(id) ON DELETE RESTRICT;


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
-- Name: social_account_accesses fk_rails_45d457e0d5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.social_account_accesses
    ADD CONSTRAINT fk_rails_45d457e0d5 FOREIGN KEY (user_identity_id) REFERENCES public.user_identities(id) ON DELETE RESTRICT;


--
-- Name: telegram_surface_bindings fk_rails_51472caa4b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telegram_surface_bindings
    ADD CONSTRAINT fk_rails_51472caa4b FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE RESTRICT;


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
-- Name: telegram_surface_bindings fk_rails_85883e6952; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telegram_surface_bindings
    ADD CONSTRAINT fk_rails_85883e6952 FOREIGN KEY (revoked_by_user_identity_id) REFERENCES public.user_identities(id) ON DELETE RESTRICT;


--
-- Name: bot_instance_lifecycle_events fk_rails_87e739aa9f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bot_instance_lifecycle_events
    ADD CONSTRAINT fk_rails_87e739aa9f FOREIGN KEY (bot_instance_id) REFERENCES public.bot_instances(id) ON DELETE RESTRICT;


--
-- Name: bot_instances fk_rails_90812beda1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bot_instances
    ADD CONSTRAINT fk_rails_90812beda1 FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE RESTRICT;


--
-- Name: service_principals fk_rails_a2c5538b21; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_principals
    ADD CONSTRAINT fk_rails_a2c5538b21 FOREIGN KEY (legacy_workspace_id) REFERENCES public.workspaces(id) ON DELETE RESTRICT;


--
-- Name: bot_instances fk_rails_abf0df04c6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bot_instances
    ADD CONSTRAINT fk_rails_abf0df04c6 FOREIGN KEY (service_principal_id) REFERENCES public.service_principals(id) ON DELETE RESTRICT;


--
-- Name: telegram_surface_bindings fk_rails_b581a4da35; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telegram_surface_bindings
    ADD CONSTRAINT fk_rails_b581a4da35 FOREIGN KEY (bot_instance_id) REFERENCES public.bot_instances(id) ON DELETE RESTRICT;


--
-- Name: provider_identity_bindings fk_rails_bbe051879c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_identity_bindings
    ADD CONSTRAINT fk_rails_bbe051879c FOREIGN KEY (user_identity_id) REFERENCES public.user_identities(id) ON DELETE RESTRICT;


--
-- Name: bot_instance_lifecycle_events fk_rails_c33fbc83d8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bot_instance_lifecycle_events
    ADD CONSTRAINT fk_rails_c33fbc83d8 FOREIGN KEY (actor_user_identity_id) REFERENCES public.user_identities(id) ON DELETE RESTRICT;


--
-- Name: social_account_accesses fk_rails_ea248aecc3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.social_account_accesses
    ADD CONSTRAINT fk_rails_ea248aecc3 FOREIGN KEY (social_account_id) REFERENCES public.social_accounts(id) ON DELETE RESTRICT;


-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260914020000'),
('20260913080000'),
('20260911203000'),
('20260911183000'),
('20260909120000'),
('20260828050000'),
('20260828030000'),
('20260828010000'),
('20260828000000'),
('20260827154500'),
('20260827134500'),
('20260827112400'),
('20260827094700');

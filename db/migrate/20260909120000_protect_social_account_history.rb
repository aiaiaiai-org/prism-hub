# © 2026 aiaiaiai · aiaiaiai.org

class ProtectSocialAccountHistory < ActiveRecord::Migration[8.1]
  def up
    add_check_constraint :social_accounts,
      "provider_account_id !~ '[[:cntrl:]]'",
      name: "social_accounts_account_id_control_check"

    execute <<~SQL
      CREATE FUNCTION protect_social_account_key() RETURNS trigger
      LANGUAGE plpgsql AS $function$
      BEGIN
        IF ROW(NEW.id, NEW.provider, NEW.provider_account_id)
          IS DISTINCT FROM ROW(OLD.id, OLD.provider, OLD.provider_account_id) THEN
          RAISE EXCEPTION 'social account identity is immutable'
            USING ERRCODE = '23514', CONSTRAINT = 'social_accounts_immutable_key';
        END IF;
        RETURN NEW;
      END;
      $function$;

      CREATE TRIGGER social_accounts_protect_key
        BEFORE UPDATE ON social_accounts
        FOR EACH ROW EXECUTE FUNCTION protect_social_account_key();

      CREATE FUNCTION protect_social_account_access_history() RETURNS trigger
      LANGUAGE plpgsql AS $function$
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
      $function$;

      CREATE TRIGGER social_account_accesses_protect_history
        BEFORE UPDATE OR DELETE ON social_account_accesses
        FOR EACH ROW EXECUTE FUNCTION protect_social_account_access_history();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER social_account_accesses_protect_history ON social_account_accesses;
      DROP FUNCTION protect_social_account_access_history();
      DROP TRIGGER social_accounts_protect_key ON social_accounts;
      DROP FUNCTION protect_social_account_key();
    SQL
    remove_check_constraint :social_accounts, name: "social_accounts_account_id_control_check"
  end
end

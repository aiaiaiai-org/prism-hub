# © 2026 aiaiaiai · aiaiaiai.org

class EnforcePublicUserIdGrammar < ActiveRecord::Migration[8.1]
  CONSTRAINT = "user_identities_canonical_id_check".freeze
  ALLOWED_CHARACTERS = "abcdefghijklmnopqrstuvwxyz0123456789-/:;()₴&@\".,?!''[]{}#%^*+=_\\|~<>€$£•".freeze

  def up
    remove_check_constraint :user_identities, name: CONSTRAINT
    add_check_constraint :user_identities,
      <<~SQL.squish,
        canonical_type <> 'person' OR (
          left(canonical_id, 2) = '0x'
          AND char_length(substring(canonical_id FROM 3)) BETWEEN 2 AND 32
          AND translate(substring(canonical_id FROM 3), '#{ALLOWED_CHARACTERS}', '') = ''
        )
      SQL
      name: CONSTRAINT
  end

  def down
    remove_check_constraint :user_identities, name: CONSTRAINT
    add_check_constraint :user_identities,
      "char_length(canonical_id) BETWEEN 1 AND 255",
      name: CONSTRAINT
  end
end

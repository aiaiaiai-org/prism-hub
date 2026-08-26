# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class PublicationDraftTest < Minitest::Test
  def test_rejects_provider_binding_fields_from_clients
    value = PrismHubTestSupport.publication_hash
    value.fetch("targets").first["provider_id"] = "meta.threads"

    error = assert_raises(PrismHub::InputError) do
      PrismHub::Domain::PublicationDraft.from_hash(value)
    end

    assert_equal "hub.publication.field.unknown", error.code
  end

  def test_rejects_provider_specific_variant_extensions
    value = PrismHubTestSupport.publication_hash
    value.fetch("variants").first["extensions"] = {"meta.threads.option" => true}

    error = assert_raises(PrismHub::InputError) do
      PrismHub::Domain::PublicationDraft.from_hash(value)
    end

    assert_equal "hub.publication.field.unknown", error.code
  end

  def test_freezes_nested_variant_content
    draft = PrismHub::Domain::PublicationDraft.from_hash(
      PrismHubTestSupport.publication_hash
    )

    assert draft.variants.frozen?
    assert draft.variants.first.fetch("body").frozen?
  end
end
